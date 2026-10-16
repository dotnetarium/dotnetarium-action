param([string]$ToolPackage, [string]$Version = '2.7.3')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$Published = [string]::IsNullOrEmpty($ToolPackage)
if (-not $Published) { $ToolPackage = (Resolve-Path -LiteralPath $ToolPackage).Path }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('dotnetarium-action-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$variables = @('GITHUB_WORKSPACE', 'RUNNER_TEMP', 'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY',
    'DNA_TARGET', 'DNA_VERSION', 'DNA_SETUP', 'DNA_RESTORE', 'DNA_PROJECT', 'DNA_UPLOAD',
    'DNA_CONFIG', 'DNA_CONFIGURATION', 'DNA_FRAMEWORK', 'DNA_SARIF', 'DNA_TOOL',
    'DNA_PROFILE', 'DNA_EDITORCONFIG', 'DNA_CONFIG_INCLUDE', 'DNA_CONFIG_EXCLUDE',
    'DNA_ARTIFACT', 'DNA_ARTIFACT_NAME', 'DNA_RETENTION')
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    $env:GITHUB_WORKSPACE = $scratch
    $env:RUNNER_TEMP = $scratch
    $env:GITHUB_OUTPUT = Join-Path $scratch 'outputs.txt'
    $env:GITHUB_STEP_SUMMARY = Join-Path $scratch 'summary.md'
    $env:DNA_TARGET = 'App/App.csproj'
    $env:DNA_VERSION = $Version
    $env:DNA_SETUP = 'false'
    $env:DNA_RESTORE = 'true'
    $env:DNA_PROJECT = 'false'
    $env:DNA_UPLOAD = 'false'
    $env:DNA_ARTIFACT = 'false'
    $env:DNA_ARTIFACT_NAME = 'scan-report'
    $env:DNA_RETENTION = '14'
    $env:DNA_PROFILE = ''
    $env:DNA_EDITORCONFIG = 'false'
    $env:DNA_CONFIG_INCLUDE = ''
    $env:DNA_CONFIG_EXCLUDE = ''
    $env:DNA_CONFIG = ''
    $env:DNA_CONFIGURATION = 'Release'
    $env:DNA_FRAMEWORK = 'net10.0'
    $env:DNA_SARIF = 'reports/results.sarif'
    & dotnet new classlib -o (Join-Path $scratch 'App') --framework net10.0 --no-restore | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not create Action fixture.' }
    # Exercise the default loader with inherited framework selection, as used
    # by LANCommander. An explicit TFM in the fixture hid skipped props before.
    $fixtureProject = Join-Path $scratch 'App/App.csproj'
    [xml]$fixtureXml = Get-Content -LiteralPath $fixtureProject -Raw
    $frameworkNode = $fixtureXml.SelectSingleNode('/Project/PropertyGroup/TargetFramework')
    $frameworkNode.ParentNode.RemoveChild($frameworkNode) | Out-Null
    $fixtureXml.Save($fixtureProject)
    @'
<Project><PropertyGroup>
  <TargetFramework Condition="'$(MSBuildProjectName)' != 'LANCommander.SDK' and '$(MSBuildProjectName)' != 'LANCommander.SDK.SourceGenerators' and '$(MSBuildProjectName)' != 'LANCommander.Steam'">net10.0</TargetFramework>
</PropertyGroup></Project>
'@ | Set-Content -LiteralPath (Join-Path $scratch 'Directory.Build.props')
    @'
using System.Security.Cryptography;
public static class UnsafeCrypto {
    public static void Run() { using var aes = Aes.Create(); aes.Mode = CipherMode.ECB; }
}
'@ | Set-Content -LiteralPath (Join-Path $scratch 'App/Class1.cs')
    & "$root/scripts/Prepare.ps1"
    $outputs = @{}
    foreach ($line in Get-Content -LiteralPath $env:GITHUB_OUTPUT) {
        $pair = $line.Split('=', 2); $outputs[$pair[0]] = $pair[1]
    }
    if (-not $outputs['target'].EndsWith('App.csproj')) { throw 'Target was not resolved.' }
    # Use the just-packed CLI instead of depending on a release being published.
    $env:DNA_TOOL = $outputs['tool-directory']
    $env:DNA_TARGET = $outputs['target']
    $env:DNA_SARIF = $outputs['sarif-file']
    Push-Location $scratch
    try {
        if ($Published) {
            & "$root/scripts/Install.ps1"
        } else {
            $packageVersion = ([IO.Path]::GetFileName($ToolPackage) -replace '^dotnetarium\.', '' -replace '\.nupkg$', '')
            $feed = [Security.SecurityElement]::Escape([IO.Path]::GetDirectoryName($ToolPackage))
            $installConfig = Join-Path $scratch 'local-package.config'
            "<configuration><packageSources><clear/><add key=`"local`" value=`"$feed`"/></packageSources></configuration>" | Set-Content -LiteralPath $installConfig
            $savedPackages = $env:NUGET_PACKAGES
            try {
                $env:NUGET_PACKAGES = Join-Path $scratch 'install-cache'
                & dotnet tool install dotnetarium --version $packageVersion --tool-path $env:DNA_TOOL --configfile $installConfig --no-cache | Out-Host
                if ($LASTEXITCODE -ne 0) { throw 'Could not install packed CLI.' }
            } finally { $env:NUGET_PACKAGES = $savedPackages }
        }
        & "$root/scripts/Restore.ps1"
        & "$root/scripts/Scan.ps1"
    } finally { Pop-Location }
    $report = Get-Content -LiteralPath $env:DNA_SARIF -Raw | ConvertFrom-Json
    if (@($report.runs[0].results | Where-Object ruleId -ne 'DNA9000').Count -lt 1) { throw 'Missing crypto finding.' }
    $outputText = Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw
    if ($outputText -notmatch 'exit-code=0' -or $outputText -notmatch 'sarif-ready=true') { throw 'Findings incorrectly failed the Action.' }
    if ((Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw) -notmatch 'Dotnetarium scan completed') { throw 'Missing summary.' }
    $env:DNA_PROJECT = 'true'
    $env:DNA_SARIF = Join-Path $scratch 'project.sarif'
    & "$root/scripts/Scan.ps1"
    $projectReport = Get-Content -LiteralPath $env:DNA_SARIF -Raw | ConvertFrom-Json
    if ($projectReport.runs[0].invocations[0].properties.'dotnetarium.loadingMode' -ne 'project' -or
        @($projectReport.runs[0].results | Where-Object ruleId -ne 'DNA9000').Count -lt 1) {
        throw 'Explicit project-mode scan lost its finding or used the wrong loader.'
    }
    $env:DNA_PROJECT = 'false'
    # Scope globs must arrive literally, including on Unix and with spaces.
    $credentialDirectory = Join-Path $scratch 'App/nested inputs'
    New-Item -ItemType Directory -Path $credentialDirectory | Out-Null
    $alphabet = 'aB7cD8eF9gH0jK1mN2pQ3rS4tU5vW6xYz'
    $body = -join (0..29 | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    $credentialFixture = '{"token":"ghp_' + $body + '2M5jQM"}'
    foreach ($file in 'selected.json', 'excluded.json') {
        $credentialFixture | Set-Content -LiteralPath (Join-Path $credentialDirectory $file)
    }
    @'
root = true
[*.cs]
dotnet_diagnostic.DNA0014.severity = none
'@ | Set-Content -LiteralPath (Join-Path $scratch 'App/.editorconfig')
    $env:DNA_EDITORCONFIG = 'true'
    $env:DNA_CONFIG_INCLUDE = "**/nested inputs/*.json`n`n**/*.yml"
    $env:DNA_CONFIG_EXCLUDE = "**/excluded.json`n"
    $env:DNA_SARIF = Join-Path $scratch 'scoped.sarif'
    & "$root/scripts/Scan.ps1"
    $scopedRun = (Get-Content -LiteralPath $env:DNA_SARIF -Raw | ConvertFrom-Json).runs[0]
    if (@($scopedRun.results | Where-Object ruleId -eq 'DNA0022').Count -ne 1 -or
        @($scopedRun.results | Where-Object ruleId -eq 'DNA0014').Count -ne 0) {
        throw 'Config-file globs or explicit EditorConfig suppression were not honored.'
    }
    $env:DNA_EDITORCONFIG = 'false'
    $env:DNA_CONFIG_INCLUDE = ''
    $env:DNA_CONFIG_EXCLUDE = ''
    $profileConfig = Join-Path $scratch 'App/dotnetarium.json'
    $profileJson = '{"Version":"2.0","AnalysisProfile":"max","MaxTaintAnalysisWork":1234,"ThreatModels":["local"]}'
    $profileJson | Set-Content -LiteralPath $profileConfig
    $exe = Join-Path $env:DNA_TOOL $(if ($IsWindows) { 'dotnetarium.exe' } else { 'dotnetarium' })
    $supportsProfile = [bool]((& $exe --help) -match '--analysis-profile\b')
    if ((-not $Published -or [version]$Version -ge [version]'2.7.2') -and -not $supportsProfile) {
        throw 'Expected CLI analysis-profile support is missing.'
    }
    if ($supportsProfile) {
        foreach ($profile in 'fast', 'full', 'max') {
            $env:DNA_PROFILE = $profile
            $env:DNA_SARIF = Join-Path $scratch "$profile.sarif"
            & "$root/scripts/Scan.ps1"
            $settings = (Get-Content -LiteralPath $env:DNA_SARIF -Raw | ConvertFrom-Json).runs[0].invocations[0].properties.'dotnetarium.analysisSettings'[0]
            if ($settings.profile -ne $profile -or $settings.workBudget -ne 1234 -or
                @($settings.threatModels) -notcontains 'local') { throw 'Profile override replaced repository settings.' }
        }
        if ((Get-Content -LiteralPath $profileConfig -Raw).Trim() -ne $profileJson) { throw 'Action modified repository configuration.' }
    } else {
        $env:DNA_PROFILE = 'fast'
        $env:DNA_SARIF = Join-Path $scratch 'unsupported-profile.sarif'
        $unsupportedRejected = $false
        try { & "$root/scripts/Scan.ps1" } catch {
            if ($_.Exception.Message -notmatch 'requires a CLI release') { throw }
            $unsupportedRejected = $true
        }
        if (-not $unsupportedRejected) { throw 'Unsupported profile override was silently accepted.' }
    }
    $env:DNA_PROFILE = ''
    # Unusable project input must preserve a failed invocation for upload before
    # the composite final step fails the job.
    $env:DNA_TARGET = Join-Path $scratch 'broken.csproj'
    '<Project><broken' | Set-Content -LiteralPath $env:DNA_TARGET
    $env:DNA_SARIF = Join-Path $scratch 'failed.sarif'
    & "$root/scripts/Scan.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Scan step must defer failure until SARIF can be uploaded.' }
    if ((Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw) -notmatch 'exit-code=2') { throw 'Execution failure was swallowed.' }
    $env:DNA_TARGET = '../escape.csproj'
    $env:DNA_SARIF = 'fresh.sarif'
    $env:DNA_CONFIG = ''
    $rejected = $false
    try { & "$root/scripts/Prepare.ps1" } catch { $rejected = $true }
    if (-not $rejected) { throw 'Out-of-workspace target was accepted.' }
    $env:DNA_TARGET = 'App/App.csproj'
    foreach ($invalid in @(@{ Name = 'DNA_RETENTION'; Value = '-1' },
        @{ Name = 'DNA_RETENTION'; Value = '401' }, @{ Name = 'DNA_RETENTION'; Value = '1.5' },
        @{ Name = 'DNA_PROFILE'; Value = 'unknown' }, @{ Name = 'DNA_EDITORCONFIG'; Value = 'yes' })) {
        $before = [Environment]::GetEnvironmentVariable($invalid.Name)
        [Environment]::SetEnvironmentVariable($invalid.Name, $invalid.Value)
        $rejected = $false
        try { & "$root/scripts/Prepare.ps1" } catch { $rejected = $true }
        finally { [Environment]::SetEnvironmentVariable($invalid.Name, $before) }
        if (-not $rejected) { throw "Invalid $($invalid.Name) was accepted." }
    }
    Write-Host 'Action smoke passed: real CLI finding, SARIF statuses, deferred failure and input validation.'
} finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
}
