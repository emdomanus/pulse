[CmdletBinding()]
param(
	[string]$Spec = "tests\lune\run.luau",
	[switch]$KeepRuntime
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'tools.ps1')

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
$specPath = Join-Path $repoRoot $Spec
if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) {
	throw "Pulse spec was not found at '$specPath'."
}

$lune = (Resolve-PackageTool 'lune').Path

$runtimeRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot ".pulse-tests"))
if (-not (Test-Path -LiteralPath $runtimeRoot)) {
	$null = New-Item -ItemType Directory -Path $runtimeRoot
}
if ((Get-Item -LiteralPath $runtimeRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
	throw "The generated runtime root must not be a reparse point."
}

function Remove-OwnedRuntime {
	param([string]$Path, [string]$Token)
	$resolved = [IO.Path]::GetFullPath($Path)
	if ([IO.Path]::GetDirectoryName($resolved) -ne $runtimeRoot -or [IO.Path]::GetFileName($resolved) -ne $Token) {
		throw "Refusing runtime cleanup outside its owned directory: $resolved"
	}
	$owner = Get-Content -LiteralPath (Join-Path $resolved "owner.json") -Raw | ConvertFrom-Json
	if ($owner.token -ne $Token) { throw "Runtime ownership mismatch: $resolved" }
	$entries = @((Get-Item -LiteralPath $resolved)) + @(Get-ChildItem -LiteralPath $resolved -Recurse -Force)
	if ($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
		throw "Refusing runtime cleanup containing a reparse point: $resolved"
	}
	$tracked = @(git -C $repoRoot ls-files -- ".pulse-tests/$Token")
	if ($LASTEXITCODE -ne 0 -or $tracked.Count -gt 0) { throw "Runtime must be untracked: $resolved" }
	Remove-Item -LiteralPath $resolved -Recurse -Force
}

# Recover only bounded, verifiably abandoned runs. A live owner's exclusive lock
# prevents another runner from collecting its files even if its child is starting.
$candidates = @(Get-ChildItem -LiteralPath $runtimeRoot -Directory | Select-Object -First 32)
foreach ($candidate in $candidates) {
	$ownerPath = Join-Path $candidate.FullName "owner.json"
	if (-not (Test-Path -LiteralPath $ownerPath)) { continue }
	$owner = Get-Content -LiteralPath $ownerPath -Raw | ConvertFrom-Json
	if ($owner.retained -or $owner.token -ne $candidate.Name) { continue }
	$ownerProcess = Get-Process -Id $owner.pid -ErrorAction SilentlyContinue
	if ($null -ne $ownerProcess -and $ownerProcess.StartTime.ToUniversalTime().Ticks -eq $owner.started) { continue }
	$staleLock = $null
	try {
		$staleLock = [IO.File]::Open((Join-Path $candidate.FullName "owner.lock"), "Open", "ReadWrite", "None")
	} catch [IO.IOException] { continue }
	finally { if ($null -ne $staleLock) { $staleLock.Dispose() } }
	Remove-OwnedRuntime -Path $candidate.FullName -Token $owner.token
}

$token = [Guid]::NewGuid().ToString("N")
$runPath = Join-Path $runtimeRoot $token
$null = New-Item -ItemType Directory -Path $runPath
$runLock = [IO.File]::Open((Join-Path $runPath "owner.lock"), "CreateNew", "ReadWrite", "None")
@{
	token = $token
	pid = $PID
	started = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
	retained = [bool]$KeepRuntime
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runPath "owner.json")
$previousRuntime = $env:PULSE_LUNE_RUNTIME
$env:PULSE_LUNE_RUNTIME = Join-Path $runPath "runtime"
$testExit = 1
Push-Location $repoRoot
try {
	& $lune "run" $Spec
	$testExit = $LASTEXITCODE
} finally {
	Pop-Location
	$env:PULSE_LUNE_RUNTIME = $previousRuntime
	$runLock.Dispose()
	if ($KeepRuntime) {
		Write-Host "Retained Pulse runtime: $runPath"
	} else {
		try { Remove-OwnedRuntime -Path $runPath -Token $token }
		catch {
			Write-Warning "Pulse runtime cleanup failed for ${runPath}: $_"
			if ($testExit -eq 0) { $testExit = 1 }
		}
	}
}
exit $testExit
