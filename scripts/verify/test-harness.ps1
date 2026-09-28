[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$runner = Join-Path $PSScriptRoot "tests.ps1"
$runtimeRoot = Join-Path $repoRoot ".pulse-tests"
$before = @(Get-ChildItem -LiteralPath $runtimeRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
$previousCase = $env:PULSE_HARNESS_CASE
try {
	foreach ($case in @("success", "setup-failure", "test-failure")) {
		$env:PULSE_HARNESS_CASE = $case
		$output = & pwsh -NoProfile -File $runner -Spec tests/lune/fixtures/runtimeLifecycle.luau 2>&1
		$code = $LASTEXITCODE
		if (($case -eq "success" -and $code -ne 0) -or ($case -ne "success" -and $code -eq 0)) {
			throw "Unexpected fixture outcome for ${case}: $output"
		}
		Write-Host "PASS: $case (exit $code)"
	}
	$staleToken = [Guid]::NewGuid().ToString("N")
	$stalePath = Join-Path $runtimeRoot $staleToken
	$null = New-Item -ItemType Directory -Path $stalePath
	@{ token = $staleToken; pid = 2147483647; started = 0; retained = $false } |
		ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stalePath "owner.json")
	[IO.File]::WriteAllText((Join-Path $stalePath "owner.lock"), "")
	$env:PULSE_HARNESS_CASE = "success"
	$output = & pwsh -NoProfile -File $runner -Spec tests/lune/fixtures/runtimeLifecycle.luau 2>&1
	if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $stalePath)) {
		throw "Stale runtime recovery failed: $output"
	}
	Write-Host "PASS: abandoned runtime recovery"
	$jobs = @(1..2 | ForEach-Object {
		Start-Job -ArgumentList $runner -ScriptBlock {
			param($runner)
			$env:PULSE_HARNESS_CASE = "concurrent"
			$output = & pwsh -NoProfile -File $runner -Spec tests/lune/fixtures/runtimeLifecycle.luau 2>&1
			[pscustomobject]@{ code = $LASTEXITCODE; output = ($output -join "`n") }
		}
	})
	try {
		$results = @($jobs | Wait-Job | Receive-Job)
		if ($results.Count -ne 2 -or @($results | Where-Object code -ne 0).Count -gt 0) {
			throw "Concurrent fixture failed: $($results | ConvertTo-Json)"
		}
		$paths = @($results | ForEach-Object { [regex]::Match($_.output, 'RUNTIME=([^\r\n]+)').Groups[1].Value })
		if ($paths[0] -eq "" -or $paths[1] -eq "" -or $paths[0] -eq $paths[1]) {
			throw "Concurrent runs did not use distinct owned paths."
		}
		Write-Host "PASS: concurrent runtime isolation"
	} finally { $jobs | Remove-Job -Force }
} finally { $env:PULSE_HARNESS_CASE = $previousCase }
$leftovers = @(Get-ChildItem -LiteralPath $runtimeRoot -Directory | Where-Object { $_.Name -notin $before })
if ($leftovers.Count -gt 0) { throw "Fixture runtime left behind: $($leftovers.FullName)" }
Write-Host "PASS: no fixture runtimes remain"
