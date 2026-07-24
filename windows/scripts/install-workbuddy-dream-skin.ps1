[CmdletBinding()]
param(
  [string]$WorkBuddyPath,
  [switch]$NoStart,
  [switch]$NoTray
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$lock = Enter-WbdsOperationLock
try {
  $sourceRoot = Get-WbdsProjectRoot
  $install = Get-WbdsWorkBuddyInstall -ExplicitPath $WorkBuddyPath
  Write-Host "Verified official WorkBuddy $($install.Version): $($install.Executable)"

  $stateRoot = Ensure-WbdsDirectory -Path (Get-WbdsStateRoot)
  $oldTrayScript = Join-Path (Get-WbdsEngineRoot) 'windows\scripts\tray-workbuddy-dream-skin.ps1'
  foreach ($process in Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue) {
    if ($process.ProcessId -ne $PID -and $process.CommandLine -and
      $process.CommandLine.IndexOf($oldTrayScript, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
    }
  }
  $engine = Install-WbdsEngine -SourceRoot $sourceRoot
  $scripts = Join-Path $engine 'windows\scripts'
  $themes = Ensure-WbdsDirectory -Path (Get-WbdsThemesDirectory)
  $active = Get-WbdsActiveThemeDirectory
  if (-not (Test-Path -LiteralPath (Join-Path $active 'theme.json') -PathType Leaf)) {
    $bundled = Join-Path $engine 'presets\gothic-void-crusade'
    Copy-Item -LiteralPath $bundled -Destination $active -Recurse -Force -ErrorAction Stop
  }

  $desktop = [Environment]::GetFolderPath('Desktop')
  $programs = [Environment]::GetFolderPath('Programs')
  $startup = [Environment]::GetFolderPath('Startup')
  New-WbdsPowerShellShortcut -Path (Join-Path $desktop 'WorkBuddy Dream Skin.lnk') `
    -Script (Join-Path $scripts 'start-workbuddy-dream-skin.ps1') -Arguments @('-PromptRestart')
  New-WbdsPowerShellShortcut -Path (Join-Path $desktop 'WorkBuddy Dream Skin - Customize.lnk') `
    -Script (Join-Path $scripts 'customize-theme-windows.ps1')
  New-WbdsPowerShellShortcut -Path (Join-Path $desktop 'WorkBuddy Dream Skin - Restore.lnk') `
    -Script (Join-Path $scripts 'restore-workbuddy-dream-skin.ps1')
  New-WbdsPowerShellShortcut -Path (Join-Path $programs 'WorkBuddy Dream Skin.lnk') `
    -Script (Join-Path $scripts 'start-workbuddy-dream-skin.ps1') -Arguments @('-PromptRestart')
  if (-not $NoTray) {
    $trayScript = Join-Path $scripts 'tray-workbuddy-dream-skin.ps1'
    New-WbdsPowerShellShortcut -Path (Join-Path $startup 'WorkBuddy Dream Skin Tray.lnk') `
      -Script $trayScript -Hidden
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden `
      -ArgumentList ((@('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', $trayScript) |
        ForEach-Object { ConvertTo-WbdsArgument -Value $_ }) -join ' ') | Out-Null
  }
  Write-Host "Installed Windows engine: $engine"
} finally {
  Exit-WbdsOperationLock -Mutex $lock
}

if (-not $NoStart) {
  & (Join-Path $scripts 'start-workbuddy-dream-skin.ps1') -PromptRestart -WorkBuddyPath $WorkBuddyPath
}
