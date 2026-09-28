#Requires -Version 7.0
[CmdletBinding()]
param([string[]]$Paths = @('src','dev','tests'))
. (Join-Path $PSScriptRoot 'tools.ps1')
$tool = Resolve-PackageTool 'stylua'
$result = Invoke-PackageTool $tool.Path (@('--check') + $Paths)
Write-Output $result.Output
exit $result.ExitCode
