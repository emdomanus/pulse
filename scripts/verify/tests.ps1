[CmdletBinding()]
param(
	[string]$Spec = "tests\lune\run.luau"
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
$specPath = Join-Path $repoRoot $Spec
if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) {
	throw "Pulse spec was not found at '$specPath'."
}

$lune = Resolve-RokitBinary "lune"

Push-Location $repoRoot
try {
	& $lune "run" $Spec
	exit $LASTEXITCODE
} finally {
	Pop-Location
}
