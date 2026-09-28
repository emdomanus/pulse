#Requires -Version 7.0
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'tools.ps1')
. (Join-Path $PSScriptRoot 'type-diagnostics.ps1')

$pwsh = (Get-Process -Id $PID).Path
$captured = Invoke-PackageTool $pwsh @('-NoProfile', '-Command', '[Console]::Out.WriteLine("stdout evidence"); [Console]::Error.WriteLine("stderr evidence"); exit 7')
if ($captured.ExitCode -ne 7 -or $captured.Output -notmatch 'stdout evidence' -or $captured.Output -notmatch 'stderr evidence') {
    throw 'Native exit code or captured streams were lost.'
}

$previous = [Environment]::GetEnvironmentVariable('LUAU_LSP_OVERRIDE', 'Process')
try {
    foreach ($case in @(
        @{ Path = 'relative-lsp.exe'; Expected = 'absolute executable path' },
        @{ Path = (Join-Path (Get-PackageRoot) '.verification/missing-lsp.exe'); Expected = 'Missing tool' },
        @{ Path = $pwsh; Expected = 'Expected luau-lsp 1.70.1' }
    )) {
        [Environment]::SetEnvironmentVariable('LUAU_LSP_OVERRIDE', $case.Path, 'Process')
        $message = ''
        try { Resolve-PackageTool 'luau-lsp' | Out-Null } catch { $message = $_.Exception.Message }
        if ($message -notmatch [regex]::Escape($case.Expected)) {
            throw "Override fixture expected '$($case.Expected)', got '$message'."
        }
    }
} finally {
    [Environment]::SetEnvironmentVariable('LUAU_LSP_OVERRIDE', $previous, 'Process')
}
Write-Output 'PASS: both native streams, exit preservation, relative/missing/wrong-version override rejection.'

$repoRoot = Get-PackageRoot
$expected = @{ 'tests/type-errors/fixture.luau:5' = $true }
$relativeHeader = 'tests/type-errors/fixture.luau(5,1): TypeError: expected rejection'
$absolutePath = Join-Path $repoRoot 'tests/type-errors/fixture.luau'
$absoluteHeader = "$absolutePath [game/ServerScriptService/fixture](5,1): TypeError: expected rejection"
$count = Test-ContractDiagnostics "$relativeHeader`n$absoluteHeader`n`tprovenance.luau(1,1): TypeError: continuation" 1 $expected $repoRoot
if ($count -ne 1) { throw 'Absolute/relative duplicates were not normalized or provenance became a diagnostic.' }
$fixtures = @(
    @{ Name = 'missing rejection'; Output = ''; Exit = 1; Expected = $expected; Message = 'missing' },
    @{ Name = 'different line'; Output = 'tests/type-errors/fixture.luau(6,1): TypeError: unrelated'; Exit = 1; Expected = $expected; Message = 'Unexpected' },
    @{ Name = 'dependency error'; Output = "$relativeHeader`nsrc/init.luau(2,1): TypeError: broken dependency"; Exit = 1; Expected = $expected; Message = 'Unexpected' },
    @{ Name = 'syntax failure'; Output = 'tests/type-errors/fixture.luau(5,1): SyntaxError: invalid syntax'; Exit = 1; Expected = $expected; Message = 'Unexpected' },
    @{ Name = 'definition failure'; Output = "[ERROR] Failed to read definitions file`n$relativeHeader"; Exit = 1; Expected = $expected; Message = 'infrastructure' },
    @{ Name = 'complexity'; Output = 'tests/type-errors/fixture.luau(5,1): TypeError: Code is too complex to typecheck!'; Exit = 1; Expected = $expected; Message = 'complexity' },
    @{ Name = 'internal error'; Output = 'tests/type-errors/fixture.luau(5,1): TypeError: Internal error: solver failure'; Exit = 1; Expected = $expected; Message = 'infrastructure' },
    @{ Name = 'successful exit'; Output = $relativeHeader; Exit = 0; Expected = $expected; Message = 'exit 1' },
    @{ Name = 'crashed process'; Output = $relativeHeader; Exit = -1; Expected = $expected; Message = 'exit 1' },
    @{ Name = 'no expectations'; Output = $relativeHeader; Exit = 1; Expected = @{}; Message = 'at least one' }
)
foreach ($fixture in $fixtures) {
    $message = ''
    try { Test-ContractDiagnostics $fixture.Output $fixture.Exit $fixture.Expected $repoRoot | Out-Null } catch { $message = $_.Exception.Message }
    if ($message -notmatch [regex]::Escape($fixture.Message)) {
        throw "Fixture '$($fixture.Name)' expected '$($fixture.Message)', got '$message'."
    }
}
Write-Output 'PASS: contract diagnostic normalization and 10 false-pass rejection fixtures.'
