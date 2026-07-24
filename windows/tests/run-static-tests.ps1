Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

$parseFailures = @()
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'windows') -Filter '*.ps1' -Recurse -File) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
  foreach ($error in @($errors)) { $parseFailures += "$($file.FullName): $($error.Message)" }
}
if ($parseFailures.Count -gt 0) { throw ($parseFailures -join "`r`n") }

$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'windows') -Filter '*.ps1' -Recurse -File)
foreach ($file in $powerShellFiles) {
  $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
  if (@($bytes | Where-Object { $_ -ge 128 }).Count -gt 0) {
    throw "Windows PowerShell source must remain ASCII unless it has a UTF-8 BOM: $($file.FullName)"
  }
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  $unsafePolicyPattern = '(?i)-ExecutionPolicy\s+' + 'By' + 'pass'
  if ($text -match $unsafePolicyPattern) { throw "Unsafe execution policy override: $($file.FullName)" }
  $asarMutationPattern = '(?i)(Set-Content|Copy-Item|Move-Item|Remove-Item).{0,100}app\.' + 'asar'
  if ($text -match $asarMutationPattern) {
    throw "A Windows script appears to mutate app.asar: $($file.FullName)"
  }
}

. (Join-Path $root 'windows\scripts\common-windows.ps1')
if (-not (Test-WbdsPathEqual -Left 'C:\Temp\One' -Right 'c:\temp\one\')) { throw 'Path equality regression.' }
if (-not (Test-WbdsPathWithin -Path 'C:\Temp\One\file.txt' -Root 'c:\temp\one')) { throw 'Path containment regression.' }
if ((ConvertTo-WbdsArgument -Value 'C:\Path With Space\file.ps1') -ne '"C:\Path With Space\file.ps1"') {
  throw 'Process argument quoting regression.'
}
foreach ($required in @(
  'windows\scripts\install-workbuddy-dream-skin.ps1',
  'windows\scripts\start-workbuddy-dream-skin.ps1',
  'windows\scripts\customize-theme-windows.ps1',
  'windows\scripts\tray-workbuddy-dream-skin.ps1',
  'windows\scripts\verify-workbuddy-dream-skin.ps1',
  'windows\scripts\restore-workbuddy-dream-skin.ps1',
  'Install WorkBuddy Dream Skin - Windows.cmd'
)) {
  if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) { throw "Missing Windows file: $required" }
}
$version = [System.IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()
$package = [System.IO.File]::ReadAllText((Join-Path $root 'package.json')) | ConvertFrom-Json
if ($version -ne "$($package.version)") { throw 'VERSION and package.json disagree.' }
Write-Host 'Windows static checks passed.'
