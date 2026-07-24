[CmdletBinding()]
param(
  [switch]$NoReopen,
  [switch]$Uninstall,
  [string]$WorkBuddyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$lock = Enter-WbdsOperationLock
try {
  $root = Get-WbdsProjectRoot
  $install = Get-WbdsWorkBuddyInstall -ExplicitPath $WorkBuddyPath
  $sessionPath = Get-WbdsSessionPath
  $state = Read-WbdsSession
  if ($null -ne $state) {
    if (-not (Test-WbdsPathEqual -Left "$($state.executable)" -Right $install.Executable)) {
      throw 'Saved WorkBuddy executable does not match the verified installation. State was preserved.'
    }
    $identity = Get-WbdsCdpIdentity -Port ([int]$state.port) -Install $install
    if ($null -ne $identity) {
      $cleanup = Invoke-WbdsNode -Install $install -Arguments @(
        (Join-Path $root 'scripts\injector.mjs'), '--port', "$($state.port)", '--cleanup', '--wait', '5'
      )
      if ($cleanup.ExitCode -ne 0) { Write-Warning 'Live cleanup did not confirm success; closing WorkBuddy clears it.' }
    }
    Stop-WbdsInjector -State $state -Install $install
    Stop-WbdsApp -Install $install -AllowForce
    Remove-Item -LiteralPath $sessionPath, (Join-Path (Get-WbdsStateRoot) 'injector.json') -Force -ErrorAction SilentlyContinue
  }

  if ($Uninstall) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $programs = [Environment]::GetFolderPath('Programs')
    $startup = [Environment]::GetFolderPath('Startup')
    foreach ($shortcut in @(
      (Join-Path $desktop 'WorkBuddy Dream Skin.lnk'),
      (Join-Path $desktop 'WorkBuddy Dream Skin - Customize.lnk'),
      (Join-Path $desktop 'WorkBuddy Dream Skin - Restore.lnk'),
      (Join-Path $programs 'WorkBuddy Dream Skin.lnk'),
      (Join-Path $startup 'WorkBuddy Dream Skin Tray.lnk')
    )) { Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue }
  }
  if (-not $NoReopen) { Start-Process -FilePath $install.Executable | Out-Null }
  Write-Host 'WorkBuddy official appearance has been restored. Saved backgrounds were preserved.'
} finally {
  Exit-WbdsOperationLock -Mutex $lock
}
