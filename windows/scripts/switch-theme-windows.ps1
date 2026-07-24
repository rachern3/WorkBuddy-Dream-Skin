[CmdletBinding(DefaultParameterSetName = 'Saved')]
param(
  [Parameter(ParameterSetName = 'Saved', Mandatory = $true)][string]$Id,
  [Parameter(ParameterSetName = 'Bundled', Mandatory = $true)][switch]$Bundled,
  [switch]$NoApply,
  [string]$WorkBuddyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$lock = Enter-WbdsOperationLock
try {
  $root = Get-WbdsProjectRoot
  $install = Get-WbdsWorkBuddyInstall -ExplicitPath $WorkBuddyPath
  $stateRoot = Ensure-WbdsDirectory -Path (Get-WbdsStateRoot)
  $source = if ($Bundled) {
    Join-Path $root 'presets\gothic-void-crusade'
  } else {
    if ($Id -cnotmatch '^[A-Za-z0-9._-]{1,96}$') { throw 'Theme id format is invalid.' }
    Join-Path (Get-WbdsThemesDirectory) $Id
  }
  if (-not (Test-Path -LiteralPath (Join-Path $source 'theme.json') -PathType Leaf)) {
    throw "Saved theme was not found: $source"
  }
  Assert-WbdsNoReparseTree -Path $source
  $probe = Invoke-WbdsNode -Install $install -Arguments @(
    (Join-Path $root 'scripts\injector.mjs'), '--validate', '--theme', $source
  )
  if ($probe.ExitCode -ne 0) { throw 'Theme validation failed: ' + ($probe.Output -join "`r`n") }

  $active = Get-WbdsActiveThemeDirectory
  $staged = Join-Path $stateRoot ('.current-theme-' + [guid]::NewGuid().ToString('N'))
  Copy-Item -LiteralPath $source -Destination $staged -Recurse -Force -ErrorAction Stop
  $backup = Join-Path $stateRoot ('.previous-theme-' + [guid]::NewGuid().ToString('N'))
  try {
    if (Test-Path -LiteralPath $active) { Move-Item -LiteralPath $active -Destination $backup -ErrorAction Stop }
    try { Move-Item -LiteralPath $staged -Destination $active -ErrorAction Stop } catch {
      if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $active)) {
        Move-Item -LiteralPath $backup -Destination $active -ErrorAction Stop
      }
      throw
    }
    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
  } finally {
    Remove-Item -LiteralPath $staged -Recurse -Force -ErrorAction SilentlyContinue
  }
  $theme = Read-WbdsJsonFile -Path (Join-Path $active 'theme.json')
  Write-Host "Selected background: $($theme.name)"
} finally {
  Exit-WbdsOperationLock -Mutex $lock
}

if (-not $NoApply) {
  & (Join-Path $PSScriptRoot 'start-workbuddy-dream-skin.ps1') `
    -PromptRestart -WorkBuddyPath $WorkBuddyPath -ThemeDirectory (Get-WbdsActiveThemeDirectory)
}
