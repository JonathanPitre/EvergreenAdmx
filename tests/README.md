# EvergreenAdmx tests

Pester suites for EvergreenAdmx. CI uses Pester 6.2.0 and PSScriptAnalyzer 1.25.0.

| Suite | File | Tag | When |
| --- | --- | --- | --- |
| Unit | `EvergreenAdmx.Tests.ps1` | _(none)_ | Every PR / push (`ci.yml`) |
| Integration | `EvergreenAdmx.Integration.Tests.ps1` | `Integration` | Release published / manual (`release-smoke.yml`) |
| Nightly | `EvergreenAdmx.Nightly.Tests.ps1` | `Nightly` | Weekly schedule / manual (`nightly.yml`) |

## Prerequisites

- Windows PowerShell 5.1+ or PowerShell 7+
- [Pester](https://pester.dev/) 6.2.0 (the version pinned in CI)
- Integration / Nightly require an elevated session (`#Requires -RunAsAdministrator`)

```powershell
Install-Module Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module Pester -RequiredVersion 6.2.0
```

CI runs unit tests under both PowerShell 7 and Windows PowerShell 5.1. Modules are cached with version-specific keys and installed only on cache misses. The same Pester cache is shared by release smoke and nightly workflows.

Unit tests cover multi-product/default `-Include` resolution at the typed script call site, Windows 11 26H2 download selection, and Snagit asset selection, archive validation, language fallback, product folders, revision stamping, and cleanup.

Lenovo Commercial Vantage unit tests use small ZIP fixtures and mocked metadata: no Enterprise ZIP download is needed. They cover dynamic discovery, aliases, exclusion from defaults, selective extraction, same-version rebuilds, language fallback, policy store copies, revision stamping, and failure cleanup. The weekly full matrix explicitly includes Lenovo and verifies its templates and version record.

Release smoke includes real Edge and Snagit downloads plus scheduled-task registration. The weekly full matrix retains all catalog products except Custom Policy Store and Windows 10; it stops on processing errors and prints verbose diagnostics. Its workflow ensures WinGet and 7-Zip are available before downloads. These suites require Windows and are separate from the fast unit suite.

## Local runs

Unit only (no admin, no downloads):

```powershell
$config = New-PesterConfiguration
$config.Run.Path = '.\tests\EvergreenAdmx.Tests.ps1'
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

## Linting

CI runs markdownlint and PSScriptAnalyzer on every PR / push (`ci.yml`). Locally:

```powershell
# PowerShell (requires PSScriptAnalyzer module)
Invoke-ScriptAnalyzer -Path .\EvergreenAdmx.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\tests -Recurse -Settings .\PSScriptAnalyzerSettings.psd1

# Markdown (requires Node / npx)
npx markdownlint-cli2 "**/*.md"
```
