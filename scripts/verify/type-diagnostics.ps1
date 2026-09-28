#Requires -Version 7.0
# Pure helpers for negative contract verification and runner fixtures.
function ConvertTo-ContractPath {
    param([string]$Path, [string]$RepoRoot)
    $root = [IO.Path]::GetFullPath($RepoRoot).Replace('\', '/').TrimEnd('/') + '/'
    $normalized = $Path.Replace('\', '/')
    $comparison = if ($root -match '^(?:[A-Za-z]:/|//)') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($normalized.StartsWith($root, $comparison)) { return $normalized.Substring($root.Length) }
    return $normalized
}

function Get-ContractExpectations {
    param([string[]]$Files, [string]$RepoRoot)
    $expected = @{}
    foreach ($file in $Files) {
        $path = ConvertTo-ContractPath $file $RepoRoot
        $lines = [IO.File]::ReadAllLines($file)
        for ($index = 0; $index -lt $lines.Length; $index++) {
            if ($lines[$index] -match '--\s*EXPECT_ERROR\s*$') {
                if ($lines[$index] -match '^\s*--') { throw "EXPECT_ERROR must follow the checked expression: ${path}:$($index + 1)." }
                $expected["${path}:$($index + 1)"] = $true
            }
        }
    }
    if ($expected.Count -eq 0) { throw 'No EXPECT_ERROR markers found.' }
    return $expected
}

function Test-ContractDiagnostics {
    param([string]$Output, [int]$ExitCode, [hashtable]$Expected, [string]$RepoRoot)
    if ($Expected.Count -eq 0) { throw 'Negative contracts require at least one expected diagnostic.' }
    if ($ExitCode -ne 1) { throw "Expected analyzer diagnostic exit 1, got $ExitCode." }
    if ($Output -match '(?m)^\[ERROR\]|Code is too complex to typecheck|Internal error:') {
        throw 'Analyzer infrastructure/complexity failure is not a rejected-contract proof.'
    }
    $seen = @{}
    foreach ($line in $Output -split '\r?\n') {
        # Require real diagnostic headers; ignore indented provenance continuations.
        if ($line -notmatch '^(?<path>\S.*?\.luau)(?:\s+\[[^\]]*\])?\((?<line>\d+),(?<column>\d+)\):\s*(?<kind>\w+):') { continue }
        $path = ConvertTo-ContractPath $Matches.path $RepoRoot
        $key = "${path}:$($Matches.line)"
        if ($Matches.kind -ne 'TypeError' -or -not $Expected.ContainsKey($key)) {
            throw "Unexpected diagnostic: $line"
        }
        $seen[$key] = $true
    }
    $missing = @($Expected.Keys | Where-Object { -not $seen.ContainsKey($_) } | Sort-Object)
    if ($missing.Count -gt 0) { throw "Expected type errors were missing: $($missing -join ', ')." }
    return $seen.Count
}
