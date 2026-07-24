[CmdletBinding()]
param([string]$OutputDirectory)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version = [System.IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()
if ($version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw "Invalid VERSION: $version" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'release' }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('workbuddy-dream-skin-release-' + [guid]::NewGuid().ToString('N'))
$packageName = "WorkBuddy-Dream-Skin-v$version-Windows"
$package = Join-Path $temporary $packageName
$output = Join-Path $OutputDirectory ($packageName + '.zip')
New-Item -ItemType Directory -Path $package -Force | Out-Null
try {
  foreach ($file in @('LICENSE', 'NOTICE.md', 'README.md', 'VERSION', 'package.json', 'Install WorkBuddy Dream Skin - Windows.cmd')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $package -Force
  }
  foreach ($directory in @('assets', 'presets', 'windows')) {
    Copy-Item -LiteralPath (Join-Path $root $directory) -Destination $package -Recurse -Force
  }
  New-Item -ItemType Directory -Path (Join-Path $package 'scripts') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $root 'scripts\injector.mjs') -Destination (Join-Path $package 'scripts') -Force
  Copy-Item -LiteralPath (Join-Path $root 'scripts\write-theme.mjs') -Destination (Join-Path $package 'scripts') -Force
  $restricted = @(Get-ChildItem -LiteralPath $package -Recurse -Force | Where-Object {
    $_.Name -match '(?i)arina|hashimoto'
  })
  if ($restricted.Count -gt 0) { throw 'Rights-restricted Arina material entered the public Windows package.' }
  Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
  Compress-Archive -LiteralPath $package -DestinationPath $output -CompressionLevel Optimal
  if (-not (Test-Path -LiteralPath $output -PathType Leaf) -or (Get-Item $output).Length -le 0) {
    throw "Release ZIP was not created: $output"
  }
  Write-Host "Created $output"
} finally {
  Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
