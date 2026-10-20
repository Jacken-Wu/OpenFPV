function Resolve-Godot {
    param([string]$ExplicitPath)
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $candidate = $ExplicitPath
    if (-not $candidate) { $candidate = $env:GODOT_EXE }
    $localFile = Join-Path $projectRoot '.local/godot-path.txt'
    if (-not $candidate -and (Test-Path -LiteralPath $localFile)) { $candidate = (Get-Content -LiteralPath $localFile -Raw).Trim() }
    if (-not $candidate) {
        $command = Get-Command godot -ErrorAction SilentlyContinue
        if ($command) { $candidate = $command.Source }
    }
    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate)) { throw 'Set GODOT_EXE, pass -GodotPath, or create .local/godot-path.txt with the Godot console executable path.' }
    $version = (& $candidate --version | Out-String).Trim()
    if ($version -notmatch '^4\.7\.2\.stable') { throw "Godot 4.7.2 required; found: $version" }
    return $candidate
}
