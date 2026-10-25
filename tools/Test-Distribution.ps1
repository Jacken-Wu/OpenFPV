param([string]$GodotPath = '', [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
if (-not $SkipBuild) {
    & "$PSScriptRoot/Build.ps1" -GodotPath $GodotPath -Configuration Debug
    & "$PSScriptRoot/Build.ps1" -GodotPath $GodotPath -Configuration Release
}
$debugDir = Join-Path $workspace 'builds/Debug'
$releaseDir = Join-Path $workspace 'builds/Release'
$debugExe = Join-Path $debugDir 'OpenFPV.exe'
$releaseExe = Join-Path $releaseDir 'OpenFPV.exe'
foreach ($name in @('README.md','README.txt','LICENSE','GODOT-NOTICES.txt','docs')) {
    if (Test-Path -LiteralPath (Join-Path $debugDir $name)) { throw "Debug contains distribution documents: $name" }
    if (Test-Path -LiteralPath (Join-Path $releaseDir $name)) { throw "Release contains external documents: $name" }
}
if (Test-Path -LiteralPath (Join-Path $releaseDir 'OpenFPV.pck')) { throw 'Release still depends on an external PCK.' }
if (@(Get-ChildItem -LiteralPath $releaseDir -Filter *.exe).Count -ne 1) { throw 'Release must have one runtime executable.' }
if (@(Get-ChildItem -LiteralPath $releaseDir -Force).Count -ne 1) { throw 'Release must contain only OpenFPV.exe.' }
$nonce = 'distribution_' + [DateTime]::UtcNow.Ticks
$logs = Join-Path $workspace ".local/test-results/$nonce"
New-Item -ItemType Directory -Force $logs | Out-Null
$reports = @()
$steps = @(
    @{Exe=$debugExe; Expected='absent'; Mark='111'; Debug=$true},
    @{Exe=$releaseExe; Expected='absent'; Mark='222'; Debug=$false},
    @{Exe=$debugExe; Expected='111'; Mark=''; Debug=$true},
    @{Exe=$releaseExe; Expected='222'; Mark=''; Debug=$false}
)
foreach ($step in $steps) {
    $log = Join-Path $logs ("channel-" + $reports.Count + '.log')
    $null = & $step.Exe --headless --log-file $log --quit-after 15000 -- --distribution-probe "--nonce=$nonce" "--expect=$($step.Expected)" "--mark=$($step.Mark)" 2>&1 | Out-String
    $body = Get-Content -LiteralPath $log -Raw
    if ($LASTEXITCODE -ne 0 -or $body -match '(?m)SCRIPT ERROR:|^ERROR:') { throw "Channel process failed: $log" }
    $json = [regex]::Match($body, '(?m)^CHANNEL_RESULT (.+)$').Groups[1].Value
    if (-not $json) { throw "Missing channel result: $log" }
    $report = $json | ConvertFrom-Json
    if (-not $report.ok -or $report.debug -ne $step.Debug) { throw "Data isolation failed: $json" }
    $reports += $report
}
if ($reports[0].directory -eq $reports[1].directory) { throw 'Debug and Release share the same user data directory.' }
$alone = Join-Path $logs 'standalone'
New-Item -ItemType Directory -Force $alone | Out-Null
$singleExe = Join-Path $alone 'OpenFPV.exe'
Copy-Item -LiteralPath $releaseExe -Destination $singleExe
$smoke = Join-Path $logs 'standalone-smoke.log'
$null = & $singleExe --headless --log-file $smoke --quit-after 15000 -- --smoke 2>&1 | Out-String
$body = Get-Content -LiteralPath $smoke -Raw
if ($LASTEXITCODE -ne 0 -or $body -match '(?m)SCRIPT ERROR:|^ERROR:' -or -not $body.Contains('SMOKE_OK')) { throw 'Release cannot run as a single independent executable.' }
$result = @{ok=$true; reports=$reports; standalone=$singleExe; debugHasNoDistributionDocs=$true; releaseOnlyExe=$true; releaseEmbedded=$true}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $workspace '.local/distribution-result.json') -Encoding utf8
Write-Host 'DISTRIBUTION_RESULT failures=0 channels=4 standalone=true'
