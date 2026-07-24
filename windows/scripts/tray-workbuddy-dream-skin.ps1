Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$trayMutex = [System.Threading.Mutex]::new($false, "Local\WorkBuddyDreamSkin.$sid.Tray")
$ownsMutex = $false
try {
  try { $ownsMutex = $trayMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
  if (-not $ownsMutex) { exit 0 }

  $notify = New-Object System.Windows.Forms.NotifyIcon
  $notify.Icon = [System.Drawing.SystemIcons]::Information
  $notify.Text = 'WorkBuddy Dream Skin'
  $notify.Visible = $true
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $notify.ContextMenuStrip = $menu

  function Start-WbdsTrayAction {
    param([string]$Script, [string[]]$Arguments = @())
    $parts = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', $Script) + $Arguments
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
      -ArgumentList (($parts | ForEach-Object { ConvertTo-WbdsArgument -Value $_ }) -join ' ') | Out-Null
  }

  function Add-WbdsTrayItem {
    param(
      [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStripItemCollection]$Items,
      [Parameter(Mandatory = $true)][string]$Text,
      [Parameter(Mandatory = $true)][scriptblock]$Action,
      [switch]$Checked
    )
    $item = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList $Text
    $item.Checked = [bool]$Checked
    $item.Add_Click($Action)
    [void]$Items.Add($item)
    return $item
  }

  $menu.Add_Opening({
    $menu.Items.Clear()
    $active = Read-WbdsJsonFile -Path (Join-Path (Get-WbdsActiveThemeDirectory) 'theme.json')
    $activeId = if ($null -ne $active) { "$($active.id)" } else { '' }
    $activeName = if ($null -ne $active) { "$($active.name)" } else { 'Bundled background' }
    $status = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList "Current: $activeName"
    $status.Enabled = $false
    [void]$menu.Items.Add($status)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    Add-WbdsTrayItem -Items $menu.Items -Text 'Choose new background...' -Action ({
      Start-WbdsTrayAction -Script (Join-Path $PSScriptRoot 'customize-theme-windows.ps1')
    }.GetNewClosure()) | Out-Null

    $switch = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList 'Quick switch background'
    [void]$menu.Items.Add($switch)
    Add-WbdsTrayItem -Items $switch.DropDownItems -Text 'Bundled: Gothic Void Crusade' `
      -Checked:($activeId -eq 'gothic-void-crusade') -Action ({
        Start-WbdsTrayAction -Script (Join-Path $PSScriptRoot 'switch-theme-windows.ps1') -Arguments @('-Bundled')
      }.GetNewClosure()) | Out-Null
    $themesRoot = Get-WbdsThemesDirectory
    if (Test-Path -LiteralPath $themesRoot -PathType Container) {
      $saved = @()
      foreach ($directory in Get-ChildItem -LiteralPath $themesRoot -Directory -Force -ErrorAction SilentlyContinue) {
        if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $theme = Read-WbdsJsonFile -Path (Join-Path $directory.FullName 'theme.json')
        if ($null -ne $theme -and "$($theme.id)" -cmatch '^[A-Za-z0-9._-]{1,96}$') {
          $saved += [pscustomobject]@{ Id = "$($theme.id)"; Name = "$($theme.name)" }
        }
      }
      if ($saved.Count -gt 0) { [void]$switch.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }
      foreach ($theme in $saved | Sort-Object Name) {
        $themeId = $theme.Id
        Add-WbdsTrayItem -Items $switch.DropDownItems -Text $theme.Name -Checked:($activeId -eq $themeId) `
          -Action ({ Start-WbdsTrayAction -Script (Join-Path $PSScriptRoot 'switch-theme-windows.ps1') -Arguments @('-Id', $themeId) }.GetNewClosure()) | Out-Null
      }
    }

    Add-WbdsTrayItem -Items $menu.Items -Text 'Reapply current background' -Action ({
      Start-WbdsTrayAction -Script (Join-Path $PSScriptRoot 'start-workbuddy-dream-skin.ps1') -Arguments @('-PromptRestart')
    }.GetNewClosure()) | Out-Null
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    Add-WbdsTrayItem -Items $menu.Items -Text 'Verify status' -Action ({
      Start-WbdsTrayAction -Script (Join-Path $PSScriptRoot 'verify-workbuddy-dream-skin.ps1')
    }.GetNewClosure()) | Out-Null
    Add-WbdsTrayItem -Items $menu.Items -Text 'Open background folder' -Action ({
      Ensure-WbdsDirectory -Path (Get-WbdsThemesDirectory) | Out-Null
      Start-Process explorer.exe -ArgumentList (ConvertTo-WbdsArgument -Value (Get-WbdsThemesDirectory)) | Out-Null
    }.GetNewClosure()) | Out-Null
    Add-WbdsTrayItem -Items $menu.Items -Text 'Restore official appearance...' -Action ({
      $answer = [System.Windows.Forms.MessageBox]::Show(
        'Stop the skin session and restore the official WorkBuddy appearance?',
        'WorkBuddy Dream Skin',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
      )
      if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-WbdsTrayAction -Script (Join-Path $PSScriptRoot 'restore-workbuddy-dream-skin.ps1')
      }
    }.GetNewClosure()) | Out-Null
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    Add-WbdsTrayItem -Items $menu.Items -Text 'Exit tray' -Action ({
      $notify.Visible = $false
      [System.Windows.Forms.Application]::Exit()
    }.GetNewClosure()) | Out-Null
  })

  $notify.Add_DoubleClick({
    Start-WbdsTrayAction -Script (Join-Path $PSScriptRoot 'customize-theme-windows.ps1')
  })
  [System.Windows.Forms.Application]::Run()
} catch {
  try { Show-WbdsMessage -Text $_.Exception.Message -Error } catch {}
  throw
} finally {
  if (Get-Variable notify -ErrorAction SilentlyContinue) {
    $notify.Visible = $false
    $notify.Dispose()
  }
  if ($ownsMutex) { try { $trayMutex.ReleaseMutex() } catch {} }
  $trayMutex.Dispose()
}
