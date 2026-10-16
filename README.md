# Dotnetarium C# Security Scan

Bring C# security findings into the place where your team already reviews code. The Dotnetarium Action runs our [open-source .NET scanner](https://github.com/dotnetarium/dotnetarium) in GitHub Actions, using the same rules and taint analysis as the command-line tool and NuGet analyzer. It follows untrusted data through your code and checks for injection, unsafe file access, exposed credentials and other security risks, with support for modern .NET frameworks and libraries.

Point it at a solution or project, and let it handle SDK setup, dependency restore, scanning and SARIF upload—or fit it into a CI job you've already prepared. Scanning uses no-build mode by default, with project mode available when you need MSBuild evaluation. Findings appear in GitHub code scanning with code locations and available data-flow paths, so reviewers can investigate the problem and understand why it matters. You get the scanner's C# security coverage with results your team can work through together.

| Setup | Use it when | What it handles |
| --- | --- | --- |
| [Standalone workflow](#standalone-scan) | Adding a separate security job | Checkout, SDKs, restore, scan and upload |
| [Action in existing CI](#existing-ci-or-private-feeds) | Reusing a prepared workspace or private feeds | Scan and upload; SDK setup and restore are optional |
| [GitHub Enterprise Server](GITHUB_ENTERPRISE.md) | Running on an on-premises GitHub instance | Runner requirements and current limitations |

The Action defaults to CLI **2.7.2** and works on GitHub-hosted Ubuntu and Windows. Self-hosted runners need PowerShell 7 (`pwsh`). SDK installation is enabled by default. The examples pin commits so adopting a newer Action is an explicit change.

See the scanner's [rule and framework coverage](https://github.com/dotnetarium/dotnetarium#what-it-checks) for the supported patterns.

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
    uses: dotnetarium/dotnetarium-action/.github/workflows/scan.yml@fa3f018805ad92a08c939f981e48e5ef3fa51c72
    with:
      target: src/MyApp.slnx
```

This installs .NET 8 and 10 SDKs, restores dependencies and scans without running `dotnet build`. Solution scans omit test projects; pass a test `.csproj` explicitly to scan it. Set `project-mode: true` when you need SDK/MSBuild design-time loading.

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
    uses: dotnetarium/dotnetarium-action/.github/workflows/scan.yml@fa3f018805ad92a08c939f981e48e5ef3fa51c72
    with:
      target: src/MyApp.slnx       # Required: repository-relative .sln, .slnx or .csproj
      version: '2.7.2'             # Exact stable CLI version, 2.7.0 or newer
      runner: ubuntu-latest        # Runner label: e.g. ubuntu-latest, windows-latest, your own label
      timeout-minutes: 20          # Positive job timeout within your runner's limits
      dotnet-version: |            # SDK versions; include .NET 10 for the scanner
        8.0.x
        10.0.x
      restore: true                # true | false; false uses already-restored dependencies
      project-mode: false          # false = no-build; true = MSBuild design-time loading
      configuration: Debug         # Your project configuration, e.g. Debug or Release
      framework: ''                # '' = automatic; net8.0 | net10.0
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
  uses: dotnetarium/dotnetarium-action@5ed964d1d7a35cc898b3d746d02928399d4ed020
  with:
    target: src/MyApp.slnx
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

The scanner itself needs .NET 10; project loading also needs the appropriate SDKs/reference packs. By default the Action installs .NET 8 and 10. Project restore uses your repository's feeds and authentication. CLI installation uses a separate NuGet.org configuration, so project feeds and `global.json` do not redirect tool installation. Restored files do not automatically transfer between jobs.

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
