[CmdletBinding()]
param(
  [int]$Port = 9432,
  [switch]$RestartExisting,
  [switch]$PromptRestart,
  [string]$WorkBuddyPath,
  [string]$ThemeDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$lock = Enter-WbdsOperationLock
try {
  Assert-WbdsPort -Port $Port
  $root = Get-WbdsProjectRoot
  $stateRoot = Ensure-WbdsDirectory -Path (Get-WbdsStateRoot)
  $install = Get-WbdsWorkBuddyInstall -ExplicitPath $WorkBuddyPath
  $sessionPath = Get-WbdsSessionPath
  $injector = Join-Path $root 'scripts\injector.mjs'
  $selectors = Join-Path $root 'assets\selectors.json'
  $stdout = Join-Path $stateRoot 'injector.log'
  $stderr = Join-Path $stateRoot 'injector-error.log'
  if (-not $ThemeDirectory) {
    $active = Get-WbdsActiveThemeDirectory
    $ThemeDirectory = if (Test-Path -LiteralPath (Join-Path $active 'theme.json') -PathType Leaf) {
      $active
    } else {
      Join-Path $root 'presets\gothic-void-crusade'
    }
  }
  $ThemeDirectory = [System.IO.Path]::GetFullPath($ThemeDirectory)
  if (-not (Test-Path -LiteralPath (Join-Path $ThemeDirectory 'theme.json') -PathType Leaf)) {
    throw "Theme directory is invalid: $ThemeDirectory"
  }
  $themeProbe = Invoke-WbdsNode -Install $install -Arguments @($injector, '--validate', '--theme', $ThemeDirectory)
  if ($themeProbe.ExitCode -ne 0) { throw 'Theme validation failed: ' + ($themeProbe.Output -join "`r`n") }

  $previousState = Read-WbdsSession
  if ($null -ne $previousState -and $previousState.port) {
    $savedPort = [int]$previousState.port
    Assert-WbdsPort -Port $savedPort
    if (-not $PSBoundParameters.ContainsKey('Port')) { $Port = $savedPort }
  }

  $identity = Get-WbdsCdpIdentity -Port $Port -Install $install
  if ($null -eq $identity) {
    $running = @(Get-WbdsAppProcesses -Install $install)
    if ($running.Count -gt 0) {
      $authorized = [bool]$RestartExisting
      if (-not $authorized -and $PromptRestart) {
        Add-Type -AssemblyName System.Windows.Forms
        $answer = [System.Windows.Forms.MessageBox]::Show(
          'WorkBuddy must restart once to enable Dream Skin. Restart now?',
          'WorkBuddy Dream Skin',
          [System.Windows.Forms.MessageBoxButtons]::YesNo,
          [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        $authorized = $answer -eq [System.Windows.Forms.DialogResult]::Yes
      }
      if (-not $authorized) {
        throw 'WorkBuddy is already open without a verified skin session. Close it or use -RestartExisting.'
      }
      # RestartExisting or the confirmation dialog explicitly authorizes a
      # restart. Electron can keep background processes alive after WM_CLOSE,
      # so allow the verified fallback termination path in that case.
      Stop-WbdsApp -Install $install -AllowForce
    }
    if (-not (Test-WbdsPortAvailable -Port $Port)) {
      if ($PSBoundParameters.ContainsKey('Port')) { throw "Port $Port is occupied by an unverified process." }
      $Port = Select-WbdsPort -PreferredPort $Port
    }

    $app = Start-WbdsExecutable -Install $install `
      -Arguments @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port") `
      -Environment @{ WORKBUDDY_REMOTE_DEBUGGING_PORT = "$Port" }
    $deadline = (Get-Date).AddSeconds(45)
    do {
      Start-Sleep -Milliseconds 350
      $identity = Get-WbdsCdpIdentity -Port $Port -Install $install
      if ($null -ne $identity) { break }
      if ($app.HasExited -and @(Get-WbdsAppProcesses -Install $install).Count -eq 0) {
        throw 'WorkBuddy exited before opening its loopback debugging port.'
      }
    } while ((Get-Date) -lt $deadline)
    if ($null -eq $identity) {
      try { Stop-WbdsApp -Install $install -AllowForce } catch {}
      throw "WorkBuddy did not open a verified loopback endpoint on port $Port."
    }
  }

  if ($null -ne $previousState) {
    try { Stop-WbdsInjector -State $previousState -Install $install } catch {
      throw 'The previous injector could not be verified and stopped: ' + $_.Exception.Message
    }
  }
  Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
  $daemon = Start-WbdsExecutable -Install $install -Hidden `
    -Arguments @($injector, '--port', "$Port", '--watch', '--theme', $ThemeDirectory, '--state', (Join-Path $stateRoot 'injector.json')) `
    -Environment @{ ELECTRON_RUN_AS_NODE = '1' } -Stdout $stdout -Stderr $stderr
  Start-Sleep -Milliseconds 600
  if ($daemon.HasExited) { throw "The injector exited during startup. See $stderr" }

  $healthy = $false
  $healthText = ''
  $deadline = (Get-Date).AddSeconds(30)
  do {
    $status = Invoke-WbdsNode -Install $install -Arguments @($injector, '--port', "$Port", '--status', '--json')
    $healthText = $status.Output -join ''
    if ($status.ExitCode -eq 0 -and $healthText -match '"active":true' -and
      $healthText -match '"style":true' -and $healthText -match '"art":true') {
      $healthy = $true
      break
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  if (-not $healthy) {
    Stop-Process -Id $daemon.Id -Force -ErrorAction SilentlyContinue
    throw "The injected renderer did not become healthy. See $stderr"
  }

  $state = [pscustomobject]@{
    schema = 1
    platform = 'windows'
    port = $Port
    injectorPid = $daemon.Id
    injectorPath = $injector
    executable = $install.Executable
    executableVersion = $install.Version
    publisherThumbprint = $install.Thumbprint
    themeDir = $ThemeDirectory
    engineRoot = $root
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  Write-WbdsJsonFile -Path $sessionPath -Value $state
  Write-Host "WorkBuddy Dream Skin is active on 127.0.0.1:$Port."
} finally {
  Exit-WbdsOperationLock -Mutex $lock
}
