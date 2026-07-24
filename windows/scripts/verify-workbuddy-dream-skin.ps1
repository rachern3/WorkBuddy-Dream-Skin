[CmdletBinding()]
param([string]$WorkBuddyPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$lock = Enter-WbdsOperationLock
try {
  $root = Get-WbdsProjectRoot
  $install = Get-WbdsWorkBuddyInstall -ExplicitPath $WorkBuddyPath
  Write-Host "Official signature: valid ($($install.Publisher))"
  $state = Read-WbdsSession
  if ($null -eq $state) {
    Write-Host 'Skin status: not active.'
    exit 0
  }
  if (-not (Test-WbdsPathEqual -Left "$($state.executable)" -Right $install.Executable)) {
    throw 'Saved executable no longer matches the verified WorkBuddy installation.'
  }
  $identity = Get-WbdsCdpIdentity -Port ([int]$state.port) -Install $install
  if ($null -eq $identity) { throw 'Saved loopback WorkBuddy endpoint is not healthy.' }
  if ($null -eq (Get-WbdsInjectorProcess -State $state -Install $install)) {
    throw 'Saved injector is not running.'
  }
  $result = Invoke-WbdsNode -Install $install -Arguments @(
    (Join-Path $root 'scripts\injector.mjs'), '--port', "$($state.port)", '--status', '--json'
  )
  if ($result.ExitCode -ne 0 -or ($result.Output -join '') -notmatch '"active":true') {
    throw 'Renderer health verification failed: ' + ($result.Output -join "`r`n")
  }
  Write-Host 'Skin status: healthy.'
  $result.Output | ForEach-Object { Write-Host $_ }
} finally {
  Exit-WbdsOperationLock -Mutex $lock
}
