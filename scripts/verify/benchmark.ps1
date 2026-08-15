[CmdletBinding()]
param(
	[string]$Fixture = "tests\lune\benchmarks\reconciliation.bench.luau"
)

$ErrorActionPreference = "Stop"

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

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
$fixturePath = Join-Path $repoRoot $Fixture
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
	throw "Pulse benchmark was not found at '$fixturePath'."
}

$lune = Resolve-RokitBinary "lune"

Push-Location $repoRoot
try {
	& $lune "run" $Fixture
	exit $LASTEXITCODE
} finally {
	Pop-Location
}
