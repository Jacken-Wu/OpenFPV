param([ValidateSet('Debug','Release')][string]$Configuration = 'Debug')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$cache = Join-Path $workspace '.local/export-templates/4.7.2.stable'
$baseName = 'windows_' + $Configuration.ToLowerInvariant() + '_x86_64.exe'
$source = Join-Path $cache $baseName
$destination = Join-Path $cache ('openfpv_' + $baseName)
$icon = Join-Path $workspace 'game/assets/openfpv.ico'
$helper = Join-Path $PSScriptRoot 'windows_icon.cs'
$stamp = $destination + '.sha256'
$identity = ((Get-FileHash -LiteralPath $source).Hash, (Get-FileHash -LiteralPath $icon).Hash, (Get-FileHash -LiteralPath $helper).Hash) -join ':'
if (-not ('OpenFPVBuild.WindowsIcon' -as [type])) { Add-Type -Path $helper }
if ((Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $stamp) -and (Get-Content -LiteralPath $stamp -Raw).Trim() -eq $identity) { return }
# Modify only a private, unpacked template copy. The exported embedded PCK is
# appended afterwards by Godot and is never passed to UpdateResource.
Copy-Item -LiteralPath $source -Destination $destination -Force
[OpenFPVBuild.WindowsIcon]::Apply($destination, $icon)
$identity | Set-Content -LiteralPath $stamp -Encoding ascii
Write-Host "OpenFPV icon prepared: $Configuration"
