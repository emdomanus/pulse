[CmdletBinding()]
param(
	[string]$Project = "tests.project.json",
	[string]$Sourcemap = "tests-sourcemap.json",
	[string]$Definitions = "",
	[string[]]$Paths = @("src", "tests/type"),
	[switch]$NoSourcemap
)

$ErrorActionPreference = "Stop"

if (-not $Definitions) {
	$Definitions = Join-Path $PSScriptRoot "..\luau-lsp\globalTypes.d.luau"
}

function Resolve-RokitBinary {
	param([string]$Name)

	$rokitBin = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".rokit\bin"
	foreach ($fileName in @("$Name.exe", $Name)) {
		$binaryPath = Join-Path $rokitBin $fileName
		if (Test-Path -LiteralPath $binaryPath -PathType Leaf) {
			return $binaryPath
		}
	}

	throw "Rokit-managed '$Name' was not found in '$rokitBin'. Run 'rokit install' from the repository root."
}

function ConvertTo-NativeArgument {
	param([string]$Argument)

	if ($Argument -match '[\s"]') {
		return '"' + ($Argument -replace '"', '\"') + '"'
	}

	return $Argument
}

function Invoke-NativeTool {
	param(
		[string]$FilePath,
		[string[]]$ArgumentList
	)

	$stdoutPath = [System.IO.Path]::GetTempFileName()
	$stderrPath = [System.IO.Path]::GetTempFileName()
	$argumentString = ($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join " "

	try {
		$process = Start-Process `
			-FilePath $FilePath `
			-ArgumentList $argumentString `
			-NoNewWindow `
			-Wait `
			-PassThru `
			-RedirectStandardOutput $stdoutPath `
			-RedirectStandardError $stderrPath

		Get-Content -LiteralPath $stdoutPath
		Get-Content -LiteralPath $stderrPath
		$script:NativeToolExitCode = $process.ExitCode
	} finally {
		Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
	}
}

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
$definitionsPath = Resolve-Path -LiteralPath $Definitions -ErrorAction SilentlyContinue
if (-not $definitionsPath) {
	throw "Roblox definitions were not found at '$Definitions'. Run scripts/luau-lsp/fetch-roblox-types.ps1 first."
}

$rojo = Resolve-RokitBinary "rojo"
$luauLsp = Resolve-RokitBinary "luau-lsp"
$existingPaths = @($Paths | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) })
if ($existingPaths.Count -eq 0) {
	throw "No requested Luau-LSP paths exist."
}

Push-Location $repoRoot
try {
	if (-not $NoSourcemap) {
		Invoke-NativeTool $rojo @("sourcemap", $Project, "--output", $Sourcemap)
		if ($script:NativeToolExitCode -ne 0) {
			exit $script:NativeToolExitCode
		}
	}

	$analyzeArgs = @(
		"analyze",
		"--sourcemap=$Sourcemap",
		"--definitions:@roblox=$($definitionsPath.ProviderPath)"
	)
	$analyzeArgs += $existingPaths

	Invoke-NativeTool $luauLsp $analyzeArgs
	exit $script:NativeToolExitCode
} finally {
	Pop-Location
}
