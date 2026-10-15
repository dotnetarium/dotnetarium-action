$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$inVersion = $false
$version = $null
foreach ($line in Get-Content -LiteralPath (Join-Path $root 'action.yml')) {
    if ($line -eq '  version:') { $inVersion = $true; continue }
    if ($inVersion -and $line -match '^  \S') { break }
    if ($inVersion -and $line -match '^    default:\s*[''"]?(\d+\.\d+\.\d+)[''"]?\s*$') {
        $version = $Matches[1]
    }
}
if (-not $version) { throw 'Cannot read the default CLI version from action.yml.' }
# A feed/network failure must fail this check. Only a successful index response
# that lacks the exact version means publication-dependent jobs should wait.
$index = Invoke-RestMethod -Uri 'https://api.nuget.org/v3-flatcontainer/dotnetarium/index.json' -TimeoutSec 30
if ($null -eq $index.versions) { throw 'NuGet returned no version index.' }
$available = (@($index.versions) -contains $version).ToString().ToLowerInvariant()
foreach ($output in @("version=$version", "available=$available")) {
    if ($env:GITHUB_OUTPUT) { $output | Add-Content -LiteralPath $env:GITHUB_OUTPUT }
    Write-Host $output
}
if ($available -eq 'false') {
    $message = "CLI $version is not published on NuGet yet. Staged package checks still run; published composite and reusable-workflow checks wait for publication. Dispatch this workflow again after publishing."
    Write-Host "::notice title=Published CLI checks pending::$message"
    if ($env:GITHUB_STEP_SUMMARY) { $message | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
}
