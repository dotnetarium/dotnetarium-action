$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$executable = Join-Path $env:DNA_TOOL $(if ($IsWindows) { 'dotnetarium.exe' } else { 'dotnetarium' })
$scanArguments = @($env:DNA_TARGET, '--sarif', $env:DNA_SARIF, '--configuration', $env:DNA_CONFIGURATION)
if ($env:DNA_CONFIG) { $scanArguments += @('--config', $env:DNA_CONFIG) }
if ($env:DNA_FRAMEWORK) { $scanArguments += @('--framework', $env:DNA_FRAMEWORK) }
if ($env:DNA_PROJECT -eq 'true') { $scanArguments += '-p' }
if ($env:DNA_PROFILE) {
    $helpText = & $executable --help
    if ($LASTEXITCODE -ne 0 -or -not ($helpText -match '--analysis-profile\b')) {
        throw 'analysis-profile requires a CLI release supporting --analysis-profile. Upgrade version or leave the input unset to preserve repository configuration.'
    }
    $scanArguments += @('--analysis-profile', $env:DNA_PROFILE)
}
if ($env:DNA_EDITORCONFIG -eq 'true') { $scanArguments += '--respect-editorconfig' }
foreach ($scope in @(@{ Value = $env:DNA_CONFIG_INCLUDE; Flag = '--config-include' },
    @{ Value = $env:DNA_CONFIG_EXCLUDE; Flag = '--config-exclude' })) {
    foreach ($pattern in ($scope.Value -split '\r?\n')) {
        if (-not [string]::IsNullOrWhiteSpace($pattern)) { $scanArguments += @($scope.Flag, $pattern.Trim()) }
    }
}
# ArgumentList preserves literal globs on Unix, where PowerShell can expand
# wildcard arguments before invoking a native executable. No shell is involved.
$start = [Diagnostics.ProcessStartInfo]::new($executable)
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
foreach ($argument in $scanArguments) { $start.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($start)
try {
    # Drain stderr asynchronously so a full error pipe cannot block stdout.
    $stderr = $process.StandardError.ReadToEndAsync()
    while ($null -ne ($line = $process.StandardOutput.ReadLine())) { Write-Host $line }
    $process.WaitForExit()
    $errorText = $stderr.GetAwaiter().GetResult()
    if ($errorText) { Write-Host $errorText }
    $scanExit = $process.ExitCode
} finally { $process.Dispose() }
"exit-code=$scanExit" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
if (-not (Test-Path -LiteralPath $env:DNA_SARIF -PathType Leaf)) {
    throw "The CLI exited with $scanExit without producing SARIF."
}
$sarif = Get-Content -LiteralPath $env:DNA_SARIF -Raw | ConvertFrom-Json -AsHashtable
if ($sarif.version -ne '2.1.0' -or @($sarif.runs).Count -ne 1) { throw 'Unexpected SARIF document.' }
$run = $sarif.runs[0]
$findings = @($run.results | Where-Object { $_.ruleId -ne 'DNA9000' })
$invocation = @($run.invocations)[0]
$inputStatus = $invocation.properties['dotnetarium.inputStatus']
$analysisStatus = $invocation.properties['dotnetarium.analysisStatus']
if ($invocation.executionSuccessful -eq $false -and $scanExit -eq 0) {
    $scanExit = 2
    "exit-code=$scanExit" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
}
@('sarif-ready=true', "findings=$($findings.Count)", "input-status=$inputStatus", "analysis-status=$analysisStatus") |
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
$severityCounts = @{ high = 0; medium = 0; low = 0; other = 0 }
$rules = @{}
foreach ($rule in $run.tool.driver.rules) { $rules[$rule.id] = $rule }
foreach ($finding in $findings) {
    $score = 0.0
    $rule = $rules[$finding.ruleId]
    $value = if ($rule) { [string]$rule.properties['security-severity'] } else { '' }
    $validScore = [double]::TryParse($value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$score)
    $severity = if (-not $validScore) { 'other' } elseif ($score -ge 7) { 'high' } elseif ($score -ge 4) { 'medium' } else { 'low' }
    $severityCounts[$severity]++
}
$status = if ($scanExit -eq 0) { 'completed' } else { 'failed' }
@("## Dotnetarium scan $status", '',
  '| Findings | High / critical | Medium | Low | Other |', '| ---: | ---: | ---: | ---: | ---: |',
  "| $($findings.Count) | $($severityCounts.high) | $($severityCounts.medium) | $($severityCounts.low) | $($severityCounts.other) |", '',
  "Inputs: **$inputStatus** · Analysis: **$analysisStatus**. Analysis limits are informational.", '',
  'When SARIF upload is enabled, findings and available paths appear in repository code scanning.') |
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
# Return normally so the composite can upload even a failed invocation's report.
# Its final step propagates any nonzero scanner exit after upload.
$global:LASTEXITCODE = 0
