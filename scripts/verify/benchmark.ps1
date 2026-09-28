#Requires -Version 7.0
[CmdletBinding()]
param([string]$Fixture = "tests/lune/benchmarks/reconciliation.bench.luau", [switch]$KeepRuntime)
& (Join-Path $PSScriptRoot 'tests.ps1') -Spec $Fixture -KeepRuntime:$KeepRuntime
exit $LASTEXITCODE
