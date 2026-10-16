# Dotnetarium C# Security Scan

Bring C# security findings into the place where your team already reviews code. The Dotnetarium Action runs our [open-source .NET scanner](https://github.com/dotnetarium/dotnetarium) in GitHub Actions, using the same rules and taint analysis as the command-line tool and NuGet analyzer. It follows untrusted data through your code and checks for injection, unsafe file access, exposed credentials and other security risks, with support for modern .NET frameworks and libraries.

Point it at a solution or project, and let it handle SDK setup, dependency restore, scanning and SARIF upload—or fit it into a CI job you've already prepared. Scanning uses no-build mode by default, with project mode available when you need MSBuild evaluation. Findings appear in GitHub code scanning with code locations and available data-flow paths, so reviewers can investigate the problem and understand why it matters. You get the scanner's C# security coverage with results your team can work through together.

| Setup | Use it when | What it handles |
| --- | --- | --- |
| [Standalone workflow](#standalone-scan) | Adding a separate security job | Checkout, SDKs, restore, scan and upload |
| [Action in existing CI](#existing-ci-or-private-feeds) | Reusing a prepared workspace or private-feed setup | Scan and upload; SDK setup and restore are optional |

See the scanner's [rule and framework coverage](https://github.com/dotnetarium/dotnetarium#what-it-checks)
for the supported patterns. This repository contains the Action, its tests and
the reusable workflow.

The Action defaults to CLI 2.7.2. The examples pin tested commits;
update these pins deliberately when adopting a newer integration.
It is tested on GitHub-hosted Ubuntu and Windows. Self-hosted runners need
PowerShell (`pwsh`); SDK installation is enabled by default.

## Standalone scan

Add `.github/workflows/dotnetarium.yml` and change `target` to your solution or
project. Checkout, SDK setup, restore, scanning and upload are handled inside
the reusable workflow.

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
    uses: dotnetarium/dotnetarium-action/.github/workflows/scan.yml@1c91405dacdfd131fc1ef4a63579acbfd6ab9d6a
    with:
      target: src/MyApp.slnx
      version: '2.7.2'
```

This installs .NET 8 and 10 SDKs, restores the target and scans in the default
no-build mode. It does not run `dotnet build`. Solution scans omit test projects;
pass a test `.csproj` explicitly to scan it. Choose an explicit target for each
scan rather than relying on ambiguous solution discovery.

Set `project-mode: true` for SDK/MSBuild design-time loading. It does not emit an
application assembly. Configure profiles and threat models in `dotnetarium.json`;
the Action does not maintain separate analysis defaults.

## Existing CI or private feeds

Use the composite Action after your existing checkout, SDK setup, feed
authentication and restore/build steps **in the same job**:

```yaml
- name: Scan prepared workspace
  uses: dotnetarium/dotnetarium-action@f52891f299c3eeb7bcfb8600d7853d90043d8b8f
  with:
    target: src/MyApp.slnx
    setup-dotnet: 'false'
    restore: 'false'
```

Provide the job permissions shown above when uploading. Restored assets do not
automatically transfer between jobs. Private-feed authentication remains in your
existing setup; the Action does not request a PAT or store feed credentials.
Scanner installation uses an isolated NuGet.org configuration, outside the
checkout, so project feeds and `global.json` do not redirect tool installation.
Target restore still honors the repository's configuration and authentication.

`dotnet restore` evaluates MSBuild projects and runs restore targets. It does not
perform a normal build, but is not a target-free operation. Disable it when using
pre-restored inputs. No-build scanning itself does not run restore or arbitrary
project targets. Missing references can reduce coverage; see [scan modes](https://github.com/dotnetarium/dotnetarium/blob/main/docs/scan-modes.md).
Restore failure fails preparation rather than silently treating it as success.

## Options

| Input | Default | Purpose |
| --- | --- | --- |
| `target` | Required | Repository-relative `.csproj`, `.sln` or `.slnx` |
| `version` | `2.7.2` | Exact stable CLI release; 2.7.0 or newer |
| `setup-dotnet` | `true` | Composite only: install SDKs; disable after existing setup |
| `dotnet-version` | `8.0.x` and `10.0.x` | SDK versions; include .NET 10 for the tool and required project SDKs/reference packs |
| `restore` | `true` | Restore before scanning; disable for an already prepared workspace |
| `project-mode` | `false` | Select `-p` design-time project loading |
| `config` | Automatic discovery | Repository-relative JSON configuration |
| `analysis-profile` | Repository configuration; otherwise CLI `full` | Optional `fast`, `full` or `max` override; requires a CLI supporting `--analysis-profile` |
| `respect-editorconfig` | `false` | Honor configured rule severities and suppressions |
| `config-include` | Unset | Newline-separated credential/config-file include globs; does not filter C# source |
| `config-exclude` | Unset | Newline-separated credential/config-file exclude globs; exclusions take precedence |
| `configuration` | `Debug` | Applied to restore and scan |
| `framework` | CLI default | Select `net8.0` or `net10.0` for the root scan; restore retains the full project-reference graph |
| `sarif-file` | `dotnetarium.sarif` | Composite only: fresh repository-relative output path |
| `upload-sarif` | `true` | Disable for an artifact-only workflow |
| `upload-artifact` | Composite: `false`; reusable: `true` | Retain downloadable SARIF independently of GHAS upload |
| `artifact-retention-days` | `14` | Artifact retention; `0` inherits repository policy; subject to repository/organization limits |
| `category` | `dotnetarium` | Stable category; use distinct values for multiple targets |
| `runner` | `ubuntu-latest` | Reusable workflow only: runner label |
| `timeout-minutes` | `20` | Reusable workflow only: job timeout within runner limits; composite callers configure their own job |
| `artifact-name` | `dotnetarium-sarif` | Use a unique name for each artifact-producing scan in the same run |

The composite exposes `sarif-file`, `findings`, `input-status` and
`analysis-status`. The reusable workflow exposes the same counts and statuses
and retains SARIF as an artifact for 14 days by default, including after an upload failure.
For multiple scans
in one workspace, use distinct SARIF paths and categories. For multiple reusable
workflow calls, also use distinct artifact names. Existing output files
are rejected to prevent overwriting files or uploading stale results.

## Results and checks

- SARIF upload populates GitHub code scanning; it does not run CodeQL analysis.
- A job summary reports total findings, severity counts, input quality and
  analysis limits. Counts include existing findings, not only new alerts.
- Findings and normal analysis limits do not fail the Action. Use GitHub code
  scanning protection rules to gate new alerts at the desired severity.
- Scanner execution failures fail the job. When the CLI produces a failure
  report, the Action uploads it before propagating failure. Errors occurring
  before SARIF exists still fail the job without uploading a stale file.
- GitHub may show PR annotations only when finding locations intersect the diff.
  Scan the whole target to retain interprocedural context.

Use `pull_request`, not `pull_request_target`, to scan PR code. GitHub handles
fork/Dependabot token restrictions; repository policies may require approval
before those workflows execute. Do not expose privileged credentials to
untrusted PR code or its restore targets.

Public repositories support code scanning. Private organization repositories
need GitHub Code Security enabled. Without it, set `upload-sarif: false`, retain
the job summary and upload `steps.scan.outputs.sarif-file` using your artifact
workflow. An App does not bypass that entitlement.

## Analysis and report controls

Use `config` for custom taint models, threat models and numeric depth/work limits.
An omitted `analysis-profile` preserves each project's configured profile; the
CLI otherwise defaults to `full`. An explicit profile overrides that selection
without replacing custom models or explicit numeric limits. Profiles change
analysis effort, not the security rule catalog. The Action never rewrites your
configuration file.

CLI 2.7.2 adds the `--analysis-profile` option. Requesting a profile with an older,
unsupported CLI fails clearly instead of silently ignoring it. When pinning an
older CLI, select profiles through `dotnetarium.json` and omit the Action input.

For example, these inputs work with CLI 2.7.2:

```yaml
with:
  target: src/MyApp.slnx
  analysis-profile: full
  respect-editorconfig: true
  config-include: |
    **/*.json
    .github/**/*.yml
  config-exclude: |
    **/fixtures/**
  upload-artifact: true
  artifact-retention-days: 7
```

Reusable workflow boolean inputs use YAML booleans; composite Action boolean
inputs may be quoted strings. Config-file globs are passed literally and do not
change C# project selection. Leave `respect-editorconfig` off to retain the CLI's
default security-rule reporting policy.

Artifact retention controls the downloadable SARIF file, not ingested GitHub
code-scanning alerts. Set `upload-artifact: false` to disable artifact storage;
set `upload-sarif: false` independently to disable GHAS upload. Public repositories
support retention up to 90 days; private repositories up to 400, subject to
organization/repository policy. `0` inherits that policy. Multiple scans need
distinct artifact names and stable, distinct code-scanning categories.

## App onboarding later

An App can open a setup PR containing the small caller workflow above and update
its pinned revision later. Normal push/PR events then execute on repository
runners. A rescan button can dispatch a workflow configured with
`workflow_dispatch`. This keeps execution, permissions and billing in the
repository without requiring Dotnetarium to host a separate scanning service.

## Integration tests

The GitHub Action integration workflow tests .NET 8/10 on Windows/Linux,
including both loaders, prepared dependencies, outputs, data flows and execution
failure handling. Its fixture deliberately contains XSS and ECB findings.
Normal PR runs retain SARIF as artifacts without publishing fixture alerts.

To test ingestion, run that workflow manually with `upload-fixture-sarif`
enabled. This creates real test alerts and GitHub's native security check may
fail because of those deliberate findings, even when the Action job succeeds.


References: [reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows),
[SARIF upload](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/integrate-with-existing-tools/upload-sarif-file),
[CodeQL C# no-build](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages).

## Development and releases

Run `pwsh -File tests/ActionSmoke/Test.ps1` to test the scripts against the
published CLI. Use `-ToolPackage <path>` to test a local scanner package instead.
Hosted CI exercises the complete Action on Windows/Linux and .NET 8/10.

Action versions are independent of scanner versions. Each release pins its
default CLI version and dependencies. Publish an Action release only after CI
passes, and document changes to the default CLI version or public inputs.

For GitHub Marketplace, publish a release with **Publish this Action to the
GitHub Marketplace** selected. The organization owner must first accept the
Marketplace Developer Agreement. The root `action.yml` provides the Action
name, description and branding. No Marketplace listing has been published yet.

## License

[Apache License 2.0](LICENSE).
