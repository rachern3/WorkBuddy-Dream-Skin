Set-StrictMode -Version Latest

function Get-WbdsProjectRoot {
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Get-WbdsStateRoot {
  if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable.' }
  return Join-Path $env:LOCALAPPDATA 'WorkBuddyDreamSkin'
}

function Get-WbdsEngineRoot {
  return Join-Path (Get-WbdsStateRoot) 'engine'
}

function Get-WbdsSessionPath {
  return Join-Path (Get-WbdsStateRoot) 'session.json'
}

function Get-WbdsActiveThemeDirectory {
  return Join-Path (Get-WbdsStateRoot) 'current-theme'
}

function Get-WbdsThemesDirectory {
  return Join-Path (Get-WbdsStateRoot) 'themes'
}

function Enter-WbdsOperationLock {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = [System.Threading.Mutex]::new($false, "Local\WorkBuddyDreamSkin.$sid.Operation")
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
  }
  if (-not $acquired) {
    $mutex.Dispose()
    throw 'Another WorkBuddy Dream Skin operation is already running.'
  }
  return $mutex
}

function Exit-WbdsOperationLock {
  param([Parameter(Mandatory = $true)][System.Threading.Mutex]$Mutex)
  try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Test-WbdsPathEqual {
  param([string]$Left, [string]$Right)
  if (-not $Left -or -not $Right) { return $false }
  try {
    $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\')
    $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
    return $leftFull -ieq $rightFull
  } catch {
    return $false
  }
}

function Test-WbdsPathWithin {
  param([string]$Path, [string]$Root)
  if (-not $Path -or -not $Root) { return $false }
  try {
    $full = [System.IO.Path]::GetFullPath($Path)
    $prefix = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Assert-WbdsNoReparseTree {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $root = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Managed path is a reparse point: $Path"
  }
  if ($root.PSIsContainer) {
    foreach ($item in Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction Stop) {
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Managed tree contains a reparse point: $($item.FullName)"
      }
    }
  }
}

function Ensure-WbdsDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or
      ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Managed directory is unsafe: $Path"
    }
  } else {
    New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
  }
  return [System.IO.Path]::GetFullPath($Path)
}

function Write-WbdsUtf8File {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
  )
  $directory = Ensure-WbdsDirectory -Path ([System.IO.Path]::GetDirectoryName($Path))
  $temporary = Join-Path $directory ('.tmp-' + [guid]::NewGuid().ToString('N'))
  try {
    [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
  }
}

function Read-WbdsJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return $text | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "JSON state is unreadable and was preserved: $Path"
  }
}

function Write-WbdsJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  Write-WbdsUtf8File -Path $Path -Content (($Value | ConvertTo-Json -Depth 8) + "`r`n")
}

function Read-WbdsSession {
  $path = Get-WbdsSessionPath
  $state = Read-WbdsJsonFile -Path $path
  if ($null -eq $state) { return $null }
  $required = @('schema', 'platform', 'port', 'injectorPid', 'injectorPath', 'executable', 'themeDir', 'engineRoot')
  foreach ($name in $required) {
    if ($state.PSObject.Properties.Name -notcontains $name -or $null -eq $state.$name -or "$($state.$name)" -eq '') {
      throw "Session state is missing $name and was preserved: $path"
    }
  }
  if ([int]$state.schema -ne 1 -or "$($state.platform)" -ne 'windows') {
    throw "Session state schema is unsupported and was preserved: $path"
  }
  $port = 0
  $pidValue = 0
  if (-not [int]::TryParse("$($state.port)", [ref]$port)) { throw "Session port is invalid: $path" }
  if (-not [int]::TryParse("$($state.injectorPid)", [ref]$pidValue) -or $pidValue -le 0) {
    throw "Session injector PID is invalid: $path"
  }
  Assert-WbdsPort -Port $port
  return $state
}

function Get-WbdsRegistryInstallCandidates {
  $roots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($root in $roots) {
    foreach ($entry in Get-ItemProperty -Path $root -ErrorAction SilentlyContinue) {
      $displayName = if ($entry.PSObject.Properties.Name -contains 'DisplayName') { "$($entry.DisplayName)" } else { '' }
      $installLocation = if ($entry.PSObject.Properties.Name -contains 'InstallLocation') { "$($entry.InstallLocation)" } else { '' }
      $displayIcon = if ($entry.PSObject.Properties.Name -contains 'DisplayIcon') { "$($entry.DisplayIcon)" } else { '' }
      $uninstallString = if ($entry.PSObject.Properties.Name -contains 'UninstallString') { "$($entry.UninstallString)" } else { '' }
      if ($displayName -notmatch '(?i)^WorkBuddy(?:\s|$)') { continue }
      if ($installLocation) { Join-Path $installLocation 'WorkBuddy.exe' }
      if ($displayIcon) {
        $icon = $displayIcon.Trim().Trim('"')
        if ($icon -match '^(?<path>.+?\.exe)(?:,\d+)?$') { $Matches.path.Trim('"') }
      }
      if ($uninstallString) {
        $uninstall = $uninstallString.Trim().Trim('"')
        $parent = Split-Path -Parent (($uninstall -split '"')[0]) -ErrorAction SilentlyContinue
        if ($parent) { Join-Path $parent 'WorkBuddy.exe' }
      }
    }
  }
}

function Assert-WbdsOfficialExecutable {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "WorkBuddy.exe was not found: $full" }
  if ([System.IO.Path]::GetFileName($full) -ine 'WorkBuddy.exe') {
    throw "Expected WorkBuddy.exe, got: $full"
  }
  $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
  if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "WorkBuddy executable cannot be a reparse point: $full"
  }
  $signature = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
  if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
    $null -eq $signature.SignerCertificate) {
    throw "WorkBuddy Authenticode signature is not valid: $full"
  }
  $subject = "$($signature.SignerCertificate.Subject)"
  $company = "$($item.VersionInfo.CompanyName)"
  $product = "$($item.VersionInfo.ProductName) $($item.VersionInfo.FileDescription)"
  if (($subject + ' ' + $company) -notmatch '(?i)Tencent|Shenzhen Tencent|\u817e\u8baf') {
    throw "WorkBuddy publisher is not recognized as Tencent: $subject / $company"
  }
  if ($product -notmatch '(?i)WorkBuddy') {
    throw "Executable product metadata is not WorkBuddy: $product"
  }
  return [pscustomobject]@{
    Executable = $full
    InstallRoot = Split-Path -Parent $full
    Version = "$($item.VersionInfo.ProductVersion)"
    Publisher = $subject
    Thumbprint = "$($signature.SignerCertificate.Thumbprint)"
  }
}

function Get-WbdsWorkBuddyInstall {
  param([string]$ExplicitPath)
  $candidates = New-Object System.Collections.Generic.List[string]
  if ($ExplicitPath) { $candidates.Add($ExplicitPath) }
  $standardCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\WorkBuddy\WorkBuddy.exe'),
    (Join-Path $env:LOCALAPPDATA 'WorkBuddy\WorkBuddy.exe')
  )
  if ($env:ProgramFiles) { $standardCandidates += Join-Path $env:ProgramFiles 'WorkBuddy\WorkBuddy.exe' }
  if (${env:ProgramFiles(x86)}) {
    $standardCandidates += Join-Path ${env:ProgramFiles(x86)} 'WorkBuddy\WorkBuddy.exe'
  }
  foreach ($candidate in $standardCandidates) {
    if ($candidate) { $candidates.Add($candidate) }
  }
  foreach ($candidate in Get-WbdsRegistryInstallCandidates) {
    if ($candidate) { $candidates.Add("$candidate") }
  }

  $seen = @{}
  $errors = @()
  foreach ($candidate in $candidates) {
    try { $full = [System.IO.Path]::GetFullPath($candidate) } catch { continue }
    if ($seen.ContainsKey($full.ToLowerInvariant())) { continue }
    $seen[$full.ToLowerInvariant()] = $true
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    try { return Assert-WbdsOfficialExecutable -Path $full } catch { $errors += $_.Exception.Message }
  }
  if ($ExplicitPath -and $errors.Count -gt 0) { throw $errors[0] }
  throw 'Official WorkBuddy.exe was not found. Install WorkBuddy or pass -WorkBuddyPath.'
}

function Get-WbdsProcessExecutablePath {
  param([Parameter(Mandatory = $true)][object]$ProcessInfo)
  if ($ProcessInfo.PSObject.Properties.Name -contains 'ExecutablePath' -and $ProcessInfo.ExecutablePath) {
    return "$($ProcessInfo.ExecutablePath)"
  }
  try { return (Get-Process -Id ([int]$ProcessInfo.ProcessId) -ErrorAction Stop).Path } catch { return $null }
}

function Get-WbdsAppProcesses {
  param([Parameter(Mandatory = $true)][object]$Install)
  return @(Get-CimInstance Win32_Process -Filter "Name = 'WorkBuddy.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $path = Get-WbdsProcessExecutablePath -ProcessInfo $_
      $command = "$($_.CommandLine)"
      (Test-WbdsPathEqual -Left $path -Right $Install.Executable) -and
        $command.IndexOf('injector.mjs', [System.StringComparison]::OrdinalIgnoreCase) -lt 0
    })
}

function Stop-WbdsApp {
  param([Parameter(Mandatory = $true)][object]$Install, [switch]$AllowForce)
  $processes = @(Get-WbdsAppProcesses -Install $Install)
  foreach ($entry in $processes) {
    try { [void](Get-Process -Id ([int]$entry.ProcessId) -ErrorAction Stop).CloseMainWindow() } catch {}
  }
  $deadline = (Get-Date).AddSeconds(15)
  while (@(Get-WbdsAppProcesses -Install $Install).Count -gt 0 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
  }
  $remaining = @(Get-WbdsAppProcesses -Install $Install)
  if ($remaining.Count -eq 0) { return }
  if (-not $AllowForce) { throw 'WorkBuddy did not close. Close it manually and retry.' }
  $deadline = (Get-Date).AddSeconds(10)
  do {
    $remaining = @(Get-WbdsAppProcesses -Install $Install)
    foreach ($entry in $remaining) {
      $current = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$entry.ProcessId)" -ErrorAction SilentlyContinue
      if ($current -and (Test-WbdsPathEqual -Left (Get-WbdsProcessExecutablePath $current) -Right $Install.Executable)) {
        Stop-Process -Id ([int]$entry.ProcessId) -Force -ErrorAction SilentlyContinue
      }
    }
    if ($remaining.Count -eq 0) { return }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  if (@(Get-WbdsAppProcesses -Install $Install).Count -gt 0) {
    throw 'Verified WorkBuddy processes remained after the authorized restart attempt.'
  }
}

function Assert-WbdsPort {
  param([int]$Port)
  if ($Port -lt 1024 -or $Port -gt 65535) { throw "Port is outside 1024-65535: $Port" }
}

function Get-WbdsPortListeners {
  param([int]$Port)
  return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Test-WbdsPortAvailable {
  param([int]$Port)
  return @(Get-WbdsPortListeners -Port $Port).Count -eq 0
}

function Select-WbdsPort {
  param([int]$PreferredPort = 9432)
  for ($port = $PreferredPort; $port -le [Math]::Min(65535, $PreferredPort + 100); $port++) {
    if (Test-WbdsPortAvailable -Port $port) { return $port }
  }
  throw 'No free loopback debugging port was found.'
}

function Test-WbdsPortOwner {
  param([int]$Port, [Parameter(Mandatory = $true)][object]$Install)
  $listeners = @(Get-WbdsPortListeners -Port $Port)
  if ($listeners.Count -eq 0) { return $false }
  foreach ($listener in $listeners) {
    if ($listener.LocalAddress -notin @('127.0.0.1', '::1')) { return $false }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$listener.OwningProcess)" -ErrorAction SilentlyContinue
    if (-not $process -or
      -not (Test-WbdsPathEqual -Left (Get-WbdsProcessExecutablePath $process) -Right $Install.Executable)) {
      return $false
    }
  }
  return $true
}

function Test-WbdsLoopbackWebSocket {
  param([string]$Value, [int]$Port)
  try {
    $uri = [Uri]$Value
    return $uri.IsAbsoluteUri -and $uri.Scheme -eq 'ws' -and $uri.Port -eq $Port -and
      $uri.Host.ToLowerInvariant() -in @('127.0.0.1', 'localhost', '::1', '[::1]') -and
      -not $uri.UserInfo -and -not $uri.Query -and -not $uri.Fragment -and
      $uri.AbsolutePath -match '^/devtools/(?:browser|page)/[A-Za-z0-9._-]{1,200}$'
  } catch { return $false }
}

function Get-WbdsCdpIdentity {
  param([int]$Port, [Parameter(Mandatory = $true)][object]$Install)
  if (-not (Test-WbdsPortOwner -Port $Port -Install $Install)) { return $null }
  try {
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 `
      -MaximumRedirection 0 -ErrorAction Stop
    if ("$($version.'User-Agent')" -notmatch 'WorkBuddy/' -or
      -not (Test-WbdsLoopbackWebSocket -Value "$($version.webSocketDebuggerUrl)" -Port $Port)) { return $null }
    $targets = @(Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2 `
      -MaximumRedirection 0 -ErrorAction Stop | Where-Object {
        "$($_.type)" -eq 'page' -and "$($_.title)" -eq 'WorkBuddy' -and
        (Test-WbdsLoopbackWebSocket -Value "$($_.webSocketDebuggerUrl)" -Port $Port)
      })
    if ($targets.Count -eq 0 -or -not (Test-WbdsPortOwner -Port $Port -Install $Install)) { return $null }
    return [pscustomobject]@{ Browser = "$($version.Browser)"; TargetCount = $targets.Count }
  } catch { return $null }
}

function ConvertTo-WbdsArgument {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  if ($Value.Contains('"')) { throw 'Double quotes are not supported in process arguments.' }
  if ($Value.Length -eq 0) { return '""' }
  if ($Value -notmatch '\s') { return $Value }
  $escaped = [regex]::Replace($Value, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

function Start-WbdsExecutable {
  param(
    [Parameter(Mandatory = $true)][object]$Install,
    [string[]]$Arguments = @(),
    [hashtable]$Environment = @{},
    [switch]$Hidden,
    [string]$Stdout,
    [string]$Stderr
  )
  $saved = @{}
  foreach ($key in $Environment.Keys) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    [Environment]::SetEnvironmentVariable($key, "$($Environment[$key])", 'Process')
  }
  try {
    $parameters = @{
      FilePath = $Install.Executable
      ArgumentList = (($Arguments | ForEach-Object { ConvertTo-WbdsArgument -Value $_ }) -join ' ')
      PassThru = $true
    }
    if ($Hidden) { $parameters['WindowStyle'] = 'Hidden' }
    if ($Stdout) { $parameters['RedirectStandardOutput'] = $Stdout }
    if ($Stderr) { $parameters['RedirectStandardError'] = $Stderr }
    return Start-Process @parameters
  } finally {
    foreach ($key in $Environment.Keys) {
      [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process')
    }
  }
}

function Invoke-WbdsNode {
  param(
    [Parameter(Mandatory = $true)][object]$Install,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  $previous = [Environment]::GetEnvironmentVariable('ELECTRON_RUN_AS_NODE', 'Process')
  [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE', '1', 'Process')
  try {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $output = @(& $Install.Executable @Arguments 2>&1 | ForEach-Object { "$_" })
      return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    } finally {
      $ErrorActionPreference = $oldPreference
    }
  } finally {
    [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE', $previous, 'Process')
  }
}

function Get-WbdsInjectorProcess {
  param([AllowNull()][object]$State, [Parameter(Mandatory = $true)][object]$Install)
  if ($null -eq $State -or -not $State.injectorPid -or -not $State.injectorPath -or -not $State.port) {
    return $null
  }
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$State.injectorPid)" -ErrorAction SilentlyContinue
  if (-not $process) { return $null }
  $path = Get-WbdsProcessExecutablePath -ProcessInfo $process
  $command = "$($process.CommandLine)"
  if (-not (Test-WbdsPathEqual -Left $path -Right $Install.Executable) -or
    $command.IndexOf("$($State.injectorPath)", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
    $command -notmatch '(?i)(?:^|\s)--watch(?:\s|$)' -or
    $command -notmatch ('(?i)(?:^|\s)--port(?:=|\s+)' + [regex]::Escape("$($State.port)") + '(?:\s|$)')) {
    throw 'Recorded injector PID does not match the saved WorkBuddy Dream Skin process.'
  }
  return $process
}

function Stop-WbdsInjector {
  param([AllowNull()][object]$State, [Parameter(Mandatory = $true)][object]$Install)
  $process = Get-WbdsInjectorProcess -State $State -Install $Install
  if ($null -eq $process) { return }
  Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
  try { Wait-Process -Id ([int]$process.ProcessId) -Timeout 8 -ErrorAction Stop } catch {}
  if (Get-Process -Id ([int]$process.ProcessId) -ErrorAction SilentlyContinue) {
    throw 'Recorded injector did not stop.'
  }
}

function Install-WbdsEngine {
  param([Parameter(Mandatory = $true)][string]$SourceRoot)
  $stateRoot = Ensure-WbdsDirectory -Path (Get-WbdsStateRoot)
  $engineRoot = Get-WbdsEngineRoot
  $staging = Join-Path $stateRoot ('.engine-staging-' + [guid]::NewGuid().ToString('N'))
  $backup = Join-Path $stateRoot ('.engine-backup-' + [guid]::NewGuid().ToString('N'))
  Ensure-WbdsDirectory -Path $staging | Out-Null
  try {
    foreach ($directory in @('assets', 'presets')) {
      Assert-WbdsNoReparseTree -Path (Join-Path $SourceRoot $directory)
      Copy-Item -LiteralPath (Join-Path $SourceRoot $directory) -Destination $staging -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path (Join-Path $staging 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'scripts\injector.mjs') -Destination (Join-Path $staging 'scripts') -Force
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'scripts\write-theme.mjs') -Destination (Join-Path $staging 'scripts') -Force
    New-Item -ItemType Directory -Path (Join-Path $staging 'windows\scripts') -Force | Out-Null
    foreach ($windowsScript in Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'windows\scripts') -Filter '*.ps1' -File) {
      Copy-Item -LiteralPath $windowsScript.FullName -Destination (Join-Path $staging 'windows\scripts') -Force
    }
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'VERSION') -Destination $staging -Force
    Assert-WbdsNoReparseTree -Path $staging
    foreach ($required in @(
      'VERSION', 'assets\renderer-inject.js', 'assets\workbuddy-dream-skin.css',
      'assets\selectors.json', 'scripts\injector.mjs', 'scripts\write-theme.mjs',
      'windows\scripts\start-workbuddy-dream-skin.ps1', 'windows\scripts\restore-workbuddy-dream-skin.ps1',
      'presets\gothic-void-crusade\background.jpg', 'presets\gothic-void-crusade\theme.json'
    )) {
      if (-not (Test-Path -LiteralPath (Join-Path $staging $required) -PathType Leaf)) {
        throw "Staged Windows engine is incomplete: $required"
      }
    }
    if (Test-Path -LiteralPath $engineRoot) { Move-Item -LiteralPath $engineRoot -Destination $backup -ErrorAction Stop }
    try { Move-Item -LiteralPath $staging -Destination $engineRoot -ErrorAction Stop } catch {
      if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $engineRoot)) {
        Move-Item -LiteralPath $backup -Destination $engineRoot -ErrorAction Stop
      }
      throw
    }
    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($script in Get-ChildItem -LiteralPath (Join-Path $engineRoot 'windows\scripts') -Filter '*.ps1' -File) {
      Unblock-File -LiteralPath $script.FullName -ErrorAction SilentlyContinue
    }
    return $engineRoot
  } finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function New-WbdsPowerShellShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Script,
    [string[]]$Arguments = @(),
    [switch]$Hidden
  )
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($Path)
  $shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
  $parts = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'RemoteSigned')
  if ($Hidden) { $parts += @('-WindowStyle', 'Hidden') }
  $parts += @('-File', $Script)
  $parts += $Arguments
  $shortcut.Arguments = ($parts | ForEach-Object { ConvertTo-WbdsArgument -Value $_ }) -join ' '
  $shortcut.WorkingDirectory = Split-Path -Parent $Script
  $shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,67"
  $shortcut.Save()
}

function Show-WbdsMessage {
  param([string]$Text, [string]$Title = 'WorkBuddy Dream Skin', [switch]$Error)
  Add-Type -AssemblyName System.Windows.Forms
  $icon = if ($Error) { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
  [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}
