#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Definitions = '',
    [string]$OutDir = '.verification/type-errors'
)
. (Join-Path $PSScriptRoot 'tools.ps1')
. (Join-Path $PSScriptRoot 'type-diagnostics.ps1')
$repoRoot = Get-PackageRoot
$files = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests/type-errors') -Filter '*.rejects.luau' -File | Sort-Object Name | ForEach-Object FullName)
$expected = Get-ContractExpectations $files $repoRoot
$evidence = [IO.Path]::GetFullPath($OutDir, $repoRoot)
# A new directory prevents a wrapper failure from reusing an earlier successful capture.
if (Test-Path -LiteralPath $evidence) { throw "Use a fresh -OutDir; '$evidence' already exists." }
$pwsh = (Get-Process -Id $PID).Path
$arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'analyze.ps1'), '-Paths', 'tests/type-errors', '-OutDir', $evidence)
if ($Definitions) { $arguments += @('-Definitions', $Definitions) }
$result = Invoke-PackageTool $pwsh $arguments
$summaryPath = Join-Path $evidence 'summary.json'
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Analyzer wrapper failed before capture: $($result.Output)" }
$summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
if (-not $summary.captureValid -or $summary.exitCode -ne $result.ExitCode) {
    throw "Analyzer capture invalid or wrapper/native exits differ. Evidence: $evidence"
}
$raw = [IO.File]::ReadAllText((Join-Path $evidence 'raw.txt'))
$count = Test-ContractDiagnostics $raw $result.ExitCode $expected $repoRoot
@{ passed = $true; rejectedExpressions = $count; expectedLocations = @($expected.Keys | Sort-Object) } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'expectations.json')
Write-Output "PASS: $count rejected expressions, no unexpected diagnostics; $evidence"
