[CmdletBinding()]
param(
	[string[]]$Paths = @("src", "dev", "tests")
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
$stylua = Resolve-RokitBinary "stylua"
$existingPaths = @($Paths | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) })

if ($existingPaths.Count -eq 0) {
	throw "No requested StyLua paths exist."
}

Push-Location $repoRoot
try {
	& $stylua "--check" @existingPaths
	exit $LASTEXITCODE
} finally {
	Pop-Location
}
