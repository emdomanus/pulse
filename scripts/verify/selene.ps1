#Requires -Version 7.0
[CmdletBinding()]
param([string[]]$Paths = @('src','dev','tests'))
. (Join-Path $PSScriptRoot 'tools.ps1')
$tool = Resolve-PackageTool 'selene'
$result = Invoke-PackageTool $tool.Path ($Paths)
Write-Output $result.Output
exit $result.ExitCode
