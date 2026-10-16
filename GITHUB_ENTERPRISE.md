# GitHub Enterprise Server

Dotnetarium can run on a self-hosted Windows or Linux runner. The current Action is exercised on GitHub.com; full GHES compatibility has not been verified yet. A few integration details need attention before using it on-premises.

## Your runner

Install PowerShell 7 (`pwsh`) and use a current Actions runner compatible with the Node 24 actions we depend on. The scanner needs .NET 10, plus the SDKs/reference packs required by your projects. If these are already installed, use the composite Action with `setup-dotnet: 'false'`.

For the reusable workflow, select your own runner label instead of its `ubuntu-latest` default:

```yaml
with:
  target: MyApp.slnx
  runner: your-scanner-runner
  upload-artifact: false
```

## Uploading results

Enable code scanning on your GHES instance and repository, with the appropriate GitHub Code Security entitlement. Check the pinned SARIF uploader against your [GHES version's supported CodeQL Action versions](https://github.com/github/codeql-action#supported-versions-of-the-codeql-bundle-on-github-enterprise-server).

**Disable built-in artifact upload for now.** Our pinned `upload-artifact@v7` does not support GHES. If you want downloadable reports, use the composite Action and add your own GHES-compatible artifact step; GitHub maintains a [v3 backport for GHES](https://github.com/actions/upload-artifact#ghes-support). This is separate from SARIF upload to code scanning.

## Network access

Your administrator must allow the Action and its dependencies through [GitHub Connect or an internal mirror](https://docs.github.com/en/enterprise-server%403.21/admin/managing-github-actions-for-your-enterprise/managing-access-to-actions-from-githubcom/about-using-actions-in-your-enterprise). Runner proxy and certificate settings also need to work with .NET and the Node-based actions.

The current installer always downloads the CLI from NuGet.org, even when SDK setup is disabled. Project restore uses your own NuGet configuration. Fully offline Action installation is not supported yet; offline environments can run a separately provisioned CLI while internal-feed/preinstalled-tool support is added to the Action.

You can disable built-in SARIF upload too (`upload-sarif: false`) and supply an uploader compatible with your GHES version after the composite scan. No scanner changes are needed to produce the SARIF file.
