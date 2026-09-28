#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Project = 'tests.project.json',
    [string]$Sourcemap = 'tests-sourcemap.json',
    [string]$Definitions = '',
    [string[]]$Paths = @('src', 'tests/type'),
    [string]$OutDir = '.verification/analyze'
)
. (Join-Path $PSScriptRoot 'tools.ps1')
$repoRoot = Get-PackageRoot
if (-not $Definitions) { $Definitions = Join-Path $PSScriptRoot '../luau-lsp/globalTypes.d.luau' }
$definitionsPath = (Resolve-Path -LiteralPath $Definitions).ProviderPath
foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path))) { throw "Missing analysis target '$path'." }
}
$rojo = Resolve-PackageTool 'rojo'
$analyzer = Resolve-PackageTool 'luau-lsp'
$generated = Invoke-PackageTool $rojo.Path @('sourcemap', $Project, '--output', $Sourcemap)
Write-Output $generated.Output
if ($generated.ExitCode -ne 0) { exit $generated.ExitCode }
$arguments = @('analyze', '--flag:LuauSolverV2=true', "--sourcemap=$Sourcemap", "--definitions:@roblox=$definitionsPath") + $Paths
Write-Output "Analyzer: $($analyzer.Path); version=$($analyzer.Version); source=$($analyzer.Source); sha256=$($analyzer.Sha256); solver=V2"
$result = Invoke-PackageTool $analyzer.Path $arguments
$evidence = [IO.Path]::GetFullPath($OutDir, $repoRoot)
New-Item -ItemType Directory -Force $evidence | Out-Null
[IO.File]::WriteAllText((Join-Path $evidence 'raw.txt'), $result.Output)
$summary = [ordered]@{
    captureValid = $result.ExitCode -in @(0, 1)
    exitCode = $result.ExitCode
    analyzer = $analyzer
    arguments = $arguments
    definitionsSha256 = (Get-FileHash -LiteralPath $definitionsPath -Algorithm SHA256).Hash
    rokitSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'rokit.toml') -Algorithm SHA256).Hash
}
$summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidence 'summary.json')
Write-Output $result.Output
exit $result.ExitCode
