# Builds one Nexus-ready zip per variant into dist/.
# A variant is the same script with different defaults in MapStreetViewSettings.reds.
param(
  [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'r6\scripts\MapStreetView'
$dist = Join-Path $root 'dist'

# Variant name -> settings to change (field name -> new value).
$variants = [ordered]@{
  'Standard'     = @{}
  'Silent'       = @{ soundEnabled = 'false' }
  'InvertedTilt' = @{ invertPitch = 'true'; mouseInvertPitch = 'true' }
  'NoMouseDrag'  = @{ mouseDragRotates = 'false' }
}

New-Item -ItemType Directory -Force $dist | Out-Null
$settingsSource = Get-Content (Join-Path $scripts 'MapStreetViewSettings.reds') -Raw

foreach ($name in $variants.Keys) {
  $stage = Join-Path ([IO.Path]::GetTempPath()) "MapStreetView-$name-$([guid]::NewGuid())"
  $target = Join-Path $stage 'r6\scripts\MapStreetView'
  New-Item -ItemType Directory -Force $target | Out-Null
  Copy-Item (Join-Path $scripts 'MapStreetView.reds') $target

  $settings = $settingsSource
  foreach ($field in $variants[$name].Keys) {
    $pattern = "(public let $field\s*:\s*\w+\s*=\s*)[^;]+;"
    if ($settings -notmatch $pattern) { throw "Variant '$name': setting '$field' not found" }
    $settings = [regex]::Replace($settings, $pattern, "`${1}$($variants[$name][$field]);")
  }
  [IO.File]::WriteAllText((Join-Path $target 'MapStreetViewSettings.reds'), $settings, (New-Object Text.UTF8Encoding $false))

  $zip = Join-Path $dist "MapStreetView-$Version-$name.zip"
  if (Test-Path $zip) { Remove-Item $zip }
  Compress-Archive -Path (Join-Path $stage 'r6') -DestinationPath $zip
  Remove-Item -Recurse -Force $stage
  Write-Host "Built $zip"
}
