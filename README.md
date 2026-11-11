# Dotnetarium C# Security Scan

Review C# security findings directly in GitHub code scanning and pull requests, with the context needed to investigate and fix them.

Dotnetarium scans .NET 8, 10 and 11 projects and solutions with an open-source security analyzer built on Roslyn. Its taint analysis follows untrusted input through supported method calls, lambdas and framework entry points to sensitive operations. Scan without building your application, with optional MSBuild design-time loading for projects that need it.

### Findings built for GitHub code scanning

The Action uploads SARIF 2.1.0 through GitHub's SARIF uploader. Findings become native code scanning alerts that your team can triage, dismiss and track alongside other analysis tools. Alerts on changed lines can appear in pull request checks.

- **Source locations** identify the affected file, line and column so reviewers can open the code in context.
- **Data-flow paths** show the source and sink of taint findings, with available intermediate steps to help explain how untrusted input reaches the operation.
- **Security severity and CWE tags** help reviewers prioritize findings and understand the weakness being reported.
- **Rule guidance** includes an explanation, examples and remediation advice, embedded in the report and linked to the rule documentation.
- **Stable fingerprints** help GitHub track the same finding across scans and reduce duplicate alerts.

### C# security coverage

Checks cover SQL and command injection, cross-site scripting, server-side request forgery, untrusted file paths, unsafe deserialization, exposed credentials, risky cryptography and insecure application settings. Framework models include ASP.NET Core, Razor/Blazor, gRPC, SignalR, database libraries and message consumers. See the scanner's [rule and framework coverage](https://github.com/dotnetarium/dotnetarium#what-it-checks) for supported patterns.

### Fit the scan into your workflow

Start with the reusable workflow to handle checkout, SDK installation, dependency restore, scanning and report upload. Use the composite Action in an existing job to reuse your SDK setup, private-feed authentication and restored dependencies. The job summary reports finding counts and scan status, and a downloadable SARIF artifact is available for further investigation.

| Setup | Use it when | What it handles |
| --- | --- | --- |
| [Standalone workflow](#standalone-scan) | Adding a separate security job | Checkout, SDKs, restore, scan and upload |
| [Action in existing CI](#existing-ci-or-private-feeds) | Reusing a prepared workspace or private feeds | Scan and upload; SDK setup and restore are optional |
| [GitHub Enterprise Server](GITHUB_ENTERPRISE.md) | Running on an on-premises GitHub instance | Runner requirements and current limitations |

The Action defaults to CLI **2.9.0** with .NET 11 support and works on GitHub-hosted Ubuntu and Windows. Self-hosted runners need PowerShell 7 (`pwsh`). SDK installation is enabled by default. The examples pin commits and the CLI version so adopting a newer release is an explicit change.

## Standalone scan

Add `.github/workflows/dotnetarium.yml` and change `target` to your solution or project:

```yaml
name: Dotnetarium
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  security-events: write
  actions: read

jobs:
  security:
    uses: dotnetarium/dotnetarium-action/.github/workflows/scan.yml@13b3d35996930bcb0e8481ec05fd02f4ccc8eb4d
    with:
      target: src/MyApp.slnx
      version: '2.9.0'
```

This installs the .NET 8, 10 and 11 SDKs, restores dependencies and scans without running `dotnet build`. Solution scans omit test projects; pass a test `.csproj` explicitly to scan it. Set `project-mode: true` when you need SDK/MSBuild design-time loading.

## Complete configuration

This is a complete reusable workflow example with **every input set to its default**, except the required `target`. You can omit any optional input. Comments show the available choices.

```yaml
name: Dotnetarium
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  security-events: write
  actions: read

jobs:
  security:
    uses: dotnetarium/dotnetarium-action/.github/workflows/scan.yml@13b3d35996930bcb0e8481ec05fd02f4ccc8eb4d
    with:
      target: src/MyApp.slnx       # Required: repository-relative .sln, .slnx or .csproj
      version: '2.9.0'             # Exact stable CLI version, 2.7.0 or newer
      runner: ubuntu-latest        # Runner label: e.g. ubuntu-latest, windows-latest, your own label
      timeout-minutes: 20          # Positive job timeout within your runner's limits
      dotnet-version: ''           # '' = SDK defaults for the selected CLI; otherwise a version list
      restore: true                # true | false; false uses already-restored dependencies
      project-mode: false          # false = no-build; true = MSBuild design-time loading
      configuration: Debug         # Your project configuration, e.g. Debug or Release
      framework: ''                # '' = automatic; net8.0 | net10.0 | net11.0
      config: ''                   # '' = discovery; otherwise a repository-relative JSON file
      analysis-profile: ''         # '' = configured profile; fast | full | max (CLI 2.7.2+)
      respect-editorconfig: false  # true | false; apply rule severities and suppressions
      config-include: ''           # Optional newline-separated credential/config-file globs
      config-exclude: ''           # Optional newline-separated globs; exclusions take precedence
      upload-sarif: true           # true | false; upload to GitHub code scanning
      category: dotnetarium        # Stable identifier; use a different value for each scan target
      upload-artifact: true        # true | false; retain downloadable SARIF independently
      artifact-name: dotnetarium-sarif # Unique artifact name for each scan in the workflow run
      artifact-retention-days: 14  # 0 = repository policy; otherwise days within that policy
```

An empty `analysis-profile` preserves each project's configuration; the CLI otherwise uses `full`. An explicit profile changes analysis effort while preserving custom models, threat models and explicit numeric depth/work limits. Keep those detailed settings in `dotnetarium.json`.

The include/exclude globs control **credential/config-file scanning**, not C# source selection. To supply multiple patterns, replace an empty value with a YAML block:

```yaml
config-include: |
  **/*.json
  .github/**/*.yml
config-exclude: |
  **/fixtures/**
```

Artifact retention applies to the downloadable SARIF file, not ingested security alerts. Public repositories allow up to 90 days and private repositories up to 400, subject to repository and organization policy. Use `0` to inherit that policy.

## Existing CI or private feeds

Use the composite Action after checkout and any SDK setup, private-feed authentication or restore steps **in the same job**. For a workspace that is already prepared:

```yaml
- name: Scan prepared workspace
  id: scan
  uses: dotnetarium/dotnetarium-action@9bb86547c4b632198b34835856e705a46ea8361d
  with:
    target: src/MyApp.slnx
    version: '2.9.0'
    setup-dotnet: 'false'
    restore: 'false'
```

Use the job permissions from the standalone example when uploading SARIF. The scan and report inputs in the complete example also apply to the composite, with these differences:

| Input or setting | Composite Action behavior |
| --- | --- |
| `setup-dotnet` | Extra input; defaults to `'true'`. Set `'false'` when the job has the required SDKs. |
| `sarif-file` | Extra input; defaults to `dotnetarium.sarif`. Choose a fresh repository-relative path for each scan. |
| `upload-artifact` | Defaults to `'false'` in the composite, compared with `true` in the reusable workflow. |
| `runner`, `timeout-minutes` | Job settings, not composite inputs. Set `runs-on` and `timeout-minutes` on the calling job. |

Composite boolean inputs may be quoted strings; reusable workflow booleans use YAML `true` and `false`. Both forms are shown above.

CLI 2.9.0 runs on the .NET 10 or .NET 11 runtime. Earlier CLI releases require .NET 10. Project loading also needs the SDKs and reference packs for your target frameworks. The default SDK set is .NET 8 and 10, plus .NET 11 with CLI 2.9.0 or newer. Override it with `dotnet-version` when your projects need a different set.

Project restore uses your repository's feeds and authentication. CLI installation uses a separate NuGet.org configuration, so project feeds and `global.json` do not redirect tool installation. Restored files do not automatically transfer between jobs.

Restore evaluates MSBuild targets. Disable it for an already-restored workspace; no-build scanning itself does not run restore or arbitrary project targets. See [scan modes](https://github.com/dotnetarium/dotnetarium/blob/main/docs/scan-modes.md) for loading behavior.

## Results and pull requests

The summary shows findings by severity, analyzed projects, profiles and scanner time. Diagnostic details remain in the log and SARIF. The composite exposes `sarif-file`, `findings`, `input-status` and `analysis-status`; the reusable workflow exposes the same count and statuses. Finding counts include existing alerts.

Findings and normal analysis limits do not fail the Action. Scanner execution errors do. When a failed scan produces SARIF, enabled uploads run before the error is propagated.

Upload the full report on PRs and pushes to your default branch. GitHub handles alert tracking and PR annotations; configure repository code-scanning protection if you want to block merges on new alerts. Use stable, distinct categories and artifact names for separate scans. Within one workspace, also use distinct SARIF paths.

Use `pull_request` to scan PR code. Keep privileged credentials out of untrusted PR code and restore targets. Fork and Dependabot workflows may require approval under repository policy.

GitHub code scanning is available for public repositories; private organization repositories need GitHub Code Security enabled. Without it, set `upload-sarif: false` and use the summary or downloadable artifact. SARIF upload uses GitHub's code-scanning interface; it does not run CodeQL analysis.

For on-premises installations, see the short [GitHub Enterprise Server guide](GITHUB_ENTERPRISE.md).

## License

[Apache License 2.0](LICENSE).
