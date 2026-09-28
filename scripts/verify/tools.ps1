#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

function Get-PackageRoot { return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')) }

function Invoke-PackageTool {
    param([string]$FilePath, [string[]]$Arguments = @())
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath
    $info.WorkingDirectory = Get-PackageRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw "Could not start '$FilePath'." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
        }
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
}

function Resolve-PackageTool {
    param([string]$Name)
    $override = $null
    if ($Name -eq 'luau-lsp') {
        $override = [Environment]::GetEnvironmentVariable('LUAU_LSP_OVERRIDE', 'Process')
        if ($null -eq $override -and $IsWindows) {
            $override = [Environment]::GetEnvironmentVariable('LUAU_LSP_OVERRIDE', 'User')
        }
    }
    $binary = if ($override) {
        if (-not [IO.Path]::IsPathFullyQualified($override)) { throw 'LUAU_LSP_OVERRIDE must be an absolute executable path.' }
        [IO.Path]::GetFullPath($override)
    } else {
        $fileName = if ($IsWindows) { "$Name.exe" } else { $Name }
        Join-Path ([Environment]::GetFolderPath('UserProfile')) ".rokit/bin/$fileName"
    }
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "Missing tool '$binary'." }
    $pinPattern = '^\s*' + [regex]::Escape($Name) + '\s*=\s*"[^"@]+@(?<version>[^"]+)"'
    $version = $null
    foreach ($line in Get-Content (Join-Path (Get-PackageRoot) 'rokit.toml')) {
        if ($line -match $pinPattern) { $version = $Matches.version; break }
    }
    if (-not $version) { throw "Missing $Name pin." }
    $result = Invoke-PackageTool $binary @('--version')
    $versionPattern = '(?<![\w.+-])' + [regex]::Escape($version) + '(?![\w.+-])'
    if ($result.ExitCode -ne 0 -or $result.Output -notmatch $versionPattern) {
        throw "Expected $Name $version; got '$($result.Output.Trim())', exit $($result.ExitCode)."
    }
    return [pscustomobject]@{
        Path = $binary
        Version = $version
        Source = if ($override) { 'override' } else { 'rokit' }
        Sha256 = if ($override) { (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash } else { '' }
    }
}
