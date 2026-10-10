# EvergreenAdmx tests

Pester suites for EvergreenAdmx. CI dependency versions are defined in [.github/powershell-dependencies.psd1](../.github/powershell-dependencies.psd1).

| Suite | File | Tag | When |
| --- | --- | --- | --- |
| Unit | `EvergreenAdmx.Tests.ps1` | _(none)_ | Every PR / push (`ci.yml`) |
| Maintenance unit | `Maintenance.Tests.ps1` | _(none)_ | Every PR / push (`ci.yml`) |
| Integration | `EvergreenAdmx.Integration.Tests.ps1` | `Integration` | Release published / manual (`release-smoke.yml`) |
| Nightly | `EvergreenAdmx.Nightly.Tests.ps1` | `Nightly` | Weekly schedule / manual (`nightly.yml`) |

## Prerequisites

- Windows PowerShell 5.1+ or PowerShell 7+
- [Pester](https://pester.dev/) at the version pinned in the dependency manifest
- Integration / Nightly require an elevated session (`#Requires -RunAsAdministrator`)

```powershell
$dependencies = Import-PowerShellDataFile ./.github/powershell-dependencies.psd1
Install-Module Pester -RequiredVersion $dependencies.Pester -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -RequiredVersion $dependencies.PSScriptAnalyzer -Scope CurrentUser -Force
Import-Module Pester -RequiredVersion $dependencies.Pester
```

CI runs unit tests under both PowerShell 7 and Windows PowerShell 5.1. Modules are cached with version-specific keys and installed only on cache misses. The same Pester cache is shared by release smoke and nightly workflows.

Unit tests cover multi-product/default `-Include` resolution at the typed script call site, Windows 11 26H2 download selection, and Snagit asset selection, archive validation, language fallback, product folders, revision stamping, and cleanup.

Lenovo Commercial Vantage unit tests use small ZIP fixtures and mocked metadata: no Enterprise ZIP download is needed. They cover dynamic discovery, aliases, exclusion from defaults, selective extraction, same-version rebuilds, language fallback, policy store copies, revision stamping, and failure cleanup. The weekly full matrix explicitly includes Lenovo and verifies its templates and version record.

Release smoke includes real Edge and Snagit downloads plus scheduled-task registration. The weekly full matrix retains all catalog products except Custom Policy Store and Windows 10; it stops on processing errors and prints verbose diagnostics. Its workflow ensures WinGet and 7-Zip are available before downloads. These suites require Windows and are separate from the fast unit suite.

## Local runs

Unit only (no admin, no downloads):

```powershell
$config = New-PesterConfiguration
$config.Run.Path = @('.\tests\EvergreenAdmx.Tests.ps1', '.\tests\Maintenance.Tests.ps1')
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

Integration smoke (elevated):

```powershell
$config = New-PesterConfiguration
$config.Run.Path = '.\tests\EvergreenAdmx.Integration.Tests.ps1'
$config.Filter.Tag = @('Integration')
Invoke-Pester -Configuration $config
```

Full matrix (elevated, long-running):

```powershell
$config = New-PesterConfiguration
$config.Run.Path = '.\tests\EvergreenAdmx.Nightly.Tests.ps1'
$config.Filter.Tag = @('Nightly')
Invoke-Pester -Configuration $config
```

## Maintenance discovery

Maintenance tests use mocked vendor responses and verify update classification, generated catalog parsing, preservation of explicit selectors, future Windows families, resource validation, and paired Foxit GET probes. For live discovery under PowerShell 7 on Windows, run the commands below. Dry runs leave repository files unchanged and create no PRs; new family candidates can download and extract packages into temporary folders for validation.

```powershell
./.github/scripts/Update-Maintenance.ps1 -Kind routine -DryRun
./.github/scripts/Update-Maintenance.ps1 -Kind major -DryRun
./.github/scripts/Update-Maintenance.ps1 -Kind families -DryRun
```

## Linting

CI runs markdownlint and PSScriptAnalyzer on every PR / push (`ci.yml`). Locally:

```powershell
# PowerShell (requires PSScriptAnalyzer module)
Invoke-ScriptAnalyzer -Path .\EvergreenAdmx.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\tests -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\.github\scripts -Recurse -Settings .\PSScriptAnalyzerSettings.psd1

# Markdown (requires Node / npx)
npx markdownlint-cli2 "**/*.md"
```
