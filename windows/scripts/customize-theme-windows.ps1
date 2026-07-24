[CmdletBinding()]
param(
  [string]$Image,
  [string]$Name,
  [ValidateSet('auto', 'light', 'dark')][string]$Appearance = 'auto',
  [switch]$NoApply,
  [string]$WorkBuddyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$install = Get-WbdsWorkBuddyInstall -ExplicitPath $WorkBuddyPath
if (-not $Image) {
  Add-Type -AssemblyName System.Windows.Forms
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Title = 'Choose a WorkBuddy background image'
  $dialog.Filter = 'Images|*.jpg;*.jpeg;*.png;*.bmp;*.gif|All files|*.*'
  $dialog.Multiselect = $false
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
  $Image = $dialog.FileName
}
$Image = [System.IO.Path]::GetFullPath($Image)
if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { throw "Image was not found: $Image" }
$sourceItem = Get-Item -LiteralPath $Image -Force
if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $sourceItem.Length -gt 52428800) {
  throw 'The image must be a regular file no larger than 50 MiB.'
}
if (-not $Name) { $Name = [System.IO.Path]::GetFileNameWithoutExtension($Image) }
$Name = ($Name -replace '[\x00-\x1f]', '').Trim()
if (-not $Name) { $Name = 'My WorkBuddy Background' }
if ($Name.Length -gt 80) { $Name = $Name.Substring(0, 80) }

$themeDirectory = $null
$lock = Enter-WbdsOperationLock
try {
  Add-Type -AssemblyName System.Drawing
  $stateRoot = Ensure-WbdsDirectory -Path (Get-WbdsStateRoot)
  $themes = Ensure-WbdsDirectory -Path (Get-WbdsThemesDirectory)
  $id = 'custom-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  $themeDirectory = Join-Path $themes $id
  Ensure-WbdsDirectory -Path $themeDirectory | Out-Null
  $outputImage = Join-Path $themeDirectory 'background.jpg'
  $bitmap = $null
  $resized = $null
  $graphics = $null
  try {
    $bitmap = [System.Drawing.Image]::FromFile($Image)
    if ($bitmap.Width -le 0 -or $bitmap.Height -le 0 -or
      $bitmap.Width -gt 16384 -or $bitmap.Height -gt 16384 -or
      ([int64]$bitmap.Width * [int64]$bitmap.Height) -gt 50000000) {
      throw 'Image dimensions are unsupported.'
    }
    $scale = [Math]::Min(1.0, 3200.0 / [Math]::Max($bitmap.Width, $bitmap.Height))
    $width = [Math]::Max(1, [int][Math]::Round($bitmap.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($bitmap.Height * $scale))
    $resized = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($resized)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($bitmap, 0, 0, $width, $height)
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
    $encoder = [System.Drawing.Imaging.Encoder]::Quality
    $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
    $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($encoder, [long]86)
    $resized.Save($outputImage, $codec, $parameters)
    $parameters.Dispose()
  } finally {
    if ($graphics) { $graphics.Dispose() }
    if ($resized) { $resized.Dispose() }
    if ($bitmap) { $bitmap.Dispose() }
  }
  if ((Get-Item -LiteralPath $outputImage).Length -gt 16777216) {
    throw 'Prepared background is larger than 16 MiB.'
  }
  $root = Get-WbdsProjectRoot
  $write = Invoke-WbdsNode -Install $install -Arguments @(
    (Join-Path $root 'scripts\write-theme.mjs'), 'custom', '--output-dir', $themeDirectory,
    '--image', 'background.jpg', '--id', $id, '--name', $Name, '--appearance', $Appearance
  )
  if ($write.ExitCode -ne 0) { throw 'Theme metadata creation failed: ' + ($write.Output -join "`r`n") }
} catch {
  if ($themeDirectory -and (Test-Path -LiteralPath $themeDirectory)) {
    Remove-Item -LiteralPath $themeDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
  throw
} finally {
  Exit-WbdsOperationLock -Mutex $lock
}

& (Join-Path $PSScriptRoot 'switch-theme-windows.ps1') -Id $id -NoApply -WorkBuddyPath $WorkBuddyPath
if (-not $NoApply) {
  & (Join-Path $PSScriptRoot 'start-workbuddy-dream-skin.ps1') `
    -PromptRestart -WorkBuddyPath $WorkBuddyPath -ThemeDirectory (Get-WbdsActiveThemeDirectory)
}
