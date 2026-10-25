param([string]$Archive = '', [switch]$Download)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$target = Join-Path $workspace '.local/export-templates/4.7.2.stable'
$names = @('windows_debug_x86_64.exe', 'windows_release_x86_64.exe', 'version.txt')
New-Item -ItemType Directory -Force $target | Out-Null
if (-not $Archive -and -not $Download) {
    $complete = @($names | Where-Object { -not (Test-Path -LiteralPath (Join-Path $target $_)) }).Count -eq 0
    if (-not $complete) {
        $installed = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable'
        foreach ($name in $names) {
            $source = Join-Path $installed $name
            if (-not (Test-Path -LiteralPath $source)) { throw 'Missing Godot 4.7.2 Windows templates. Install them in Godot, use -Archive <tpz>, or run Setup-ExportTemplates.ps1 -Download.' }
            Copy-Item -LiteralPath $source -Destination (Join-Path $target $name) -Force
        }
    }
} else {
    if ($Download) {
        $Archive = Join-Path $workspace '.local/Godot_v4.7.2-stable_export_templates.tpz'
        if (-not (Test-Path -LiteralPath $Archive)) {
            Write-Host 'Downloading official Godot 4.7.2 Standard export templates (about1.28GB).'
            Invoke-WebRequest -Uri 'https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz' -OutFile $Archive -TimeoutSec 1800
        }
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Archive))
    try {
        $version = $zip.GetEntry('templates/version.txt')
        if (-not $version) { throw 'Invalid export template archive.' }
        $reader = [IO.StreamReader]::new($version.Open())
        try { $text = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
        if ($text -ne '4.7.2.stable') { throw "Godot 4.7.2.stable templates required, found $text" }
        foreach ($name in $names) {
            $entry = $zip.GetEntry("templates/$name")
            if (-not $entry) { throw "Missing Windows x64 template: $name" }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $target $name), $true)
        }
    } finally { $zip.Dispose() }
}
if ((Get-Content -LiteralPath (Join-Path $target 'version.txt') -Raw).Trim() -ne '4.7.2.stable') { throw 'Wrong cached export template version.' }
Write-Host "Windows Debug/Release templates ready: $target"
foreach ($configuration in @('Debug','Release')) { & (Join-Path $PSScriptRoot 'Prepare-ExportIcon.ps1') -Configuration $configuration }
