[CmdletBinding()]
param(
	[string]$OutFile = (Join-Path $PSScriptRoot "globalTypes.d.luau"),
	[string]$Uri = "https://luau-lsp.pages.dev/type-definitions/globalTypes.d.luau",
	[switch]$Force
)

$ErrorActionPreference = "Stop"

if ((Test-Path -LiteralPath $OutFile) -and -not $Force) {
	Write-Host "Roblox definitions already exist: $OutFile"
	Write-Host "Use -Force to refresh them."
	exit 0
}

$directory = Split-Path -Parent $OutFile
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
	New-Item -ItemType Directory -Path $directory | Out-Null
}

$temporaryFile = "$OutFile.tmp"

try {
	Invoke-WebRequest -Uri $Uri -OutFile $temporaryFile
	if (-not (Test-Path -LiteralPath $temporaryFile) -or (Get-Item -LiteralPath $temporaryFile).Length -eq 0) {
		throw "Downloaded definitions file was empty."
	}

	Move-Item -LiteralPath $temporaryFile -Destination $OutFile -Force
} finally {
	if (Test-Path -LiteralPath $temporaryFile) {
		Remove-Item -LiteralPath $temporaryFile -Force
	}
}

Write-Host "Downloaded Roblox definitions to: $OutFile"
