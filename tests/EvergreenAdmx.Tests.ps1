#Requires -Version 5.1
# Unit tests - no downloads, no admin required.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers\Import-EvergreenAdmxUnderTest.ps1')
    # Dot-source function bodies in this scope (not inside Import-*).
    foreach ($text in (Get-EvergreenAdmxFunctionText)) {
        . ([scriptblock]::Create($text))
    }
    $script:ScriptPath = Get-EvergreenAdmxScriptPath
}

Describe 'EvergreenAdmx script surface' {
    It 'parses without syntax errors' {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'places PSScriptInfo before #Requires and comment-based help' {
        $header = Get-Content -LiteralPath $script:ScriptPath -Raw
        $psScriptInfo = $header.IndexOf('<#PSScriptInfo')
        $requires = $header.IndexOf('#Requires')
        $synopsis = $header.IndexOf('.SYNOPSIS')
        $psScriptInfo | Should -BeGreaterOrEqual 0
        $requires | Should -BeGreaterThan $psScriptInfo
        $synopsis | Should -BeGreaterThan $requires
    }

    It 'declares #Requires -Version 5.1 and #Requires -RunAsAdministrator' {
        $header = Get-Content -LiteralPath $script:ScriptPath -TotalCount 50
        ($header -join "`n") | Should -Match '#Requires\s+-Version\s+5\.1'
        ($header -join "`n") | Should -Match '#Requires\s+-RunAsAdministrator'
    }

    It 'exposes expected helper functions' {
        Get-Command -Name Get-WindowsDownloadId -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name New-EvergreenAdmxTaskArgumentList -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-EvergreenAdmxObsoleteFilePattern -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Clear-ObsoleteAdmx -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Initialize-PolicyStore -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-EvergreenAdmxProductCatalog -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Resolve-EvergreenAdmxInclude -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name ConvertTo-AdmxRevisionString -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Set-AdmxRevision -CommandType Function | Should -Not -BeNullOrEmpty
    }
}

Describe 'Language tag pattern' {
    It 'accepts <Language>' -ForEach @(
        @{ Language = 'en-US' }
        @{ Language = 'es' }
        @{ Language = 'fr-FR' }
        @{ Language = 'es-419' }
        @{ Language = 'nl-NL' }
    ) {
        $Language | Should -Match $script:EvergreenAdmxLanguagePattern
    }

    It 'rejects <Language>' -ForEach @(
        @{ Language = 'english' }
        @{ Language = 'en_US' }
        @{ Language = 'e' }
        @{ Language = 'en-US-x' }
    ) {
        $Language | Should -Not -Match $script:EvergreenAdmxLanguagePattern
    }
}

Describe 'Get-WindowsDownloadId' {
    It 'returns <Expected> for Windows <WindowsVersion> / <WindowsFeatureVersion>' -ForEach @(
        @{ WindowsVersion = 10; WindowsFeatureVersion = '21H2'; Expected = '104042' }
        @{ WindowsVersion = 10; WindowsFeatureVersion = '22H2'; Expected = '104677' }
        @{ WindowsVersion = 11; WindowsFeatureVersion = '23H2'; Expected = '105667' }
        @{ WindowsVersion = 11; WindowsFeatureVersion = '24H2'; Expected = '106254' }
        @{ WindowsVersion = 11; WindowsFeatureVersion = '25H2'; Expected = '108542' }
        @{ WindowsVersion = 11; WindowsFeatureVersion = '26H2'; Expected = '108847' }
        @{ WindowsVersion = 2022; WindowsFeatureVersion = '25H2'; Expected = '104003' }
        @{ WindowsVersion = 2025; WindowsFeatureVersion = '25H2'; Expected = '108430' }
    ) {
        $id = Get-WindowsDownloadId -WindowsVersion $WindowsVersion -WindowsFeatureVersion $WindowsFeatureVersion
        if ($id -is [array]) { $id = $id[0] }
        "$id" | Should -Be $Expected
    }

    It 'rejects Windows 10 with 25H2' {
        { Get-WindowsDownloadId -WindowsVersion 10 -WindowsFeatureVersion '25H2' } |
            Should -Throw -ExpectedMessage '*Invalid Windows Feature Version*'
    }

    It 'rejects Windows 11 with 22H2' {
        { Get-WindowsDownloadId -WindowsVersion 11 -WindowsFeatureVersion '22H2' } |
            Should -Throw -ExpectedMessage '*Invalid Windows Feature Version*'
    }

    It 'defaults to the Windows 11 26H2 download' {
        Get-WindowsDownloadId | Should -Be '108847'
    }

    It 'selects the correct default feature version for Windows <WindowsVersion>' -ForEach @(
        @{ WindowsVersion = '10'; Expected = '22H2' }
        @{ WindowsVersion = '11'; Expected = '26H2' }
    ) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$errors)
        $parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'WindowsFeatureVersion' }
        & ([scriptblock]::Create($parameter.DefaultValue.Extent.Text)) | Should -Be $Expected
    }
}

Describe 'New-EvergreenAdmxTaskArgumentList' {
    BeforeAll {
        $script:FakeScript = 'D:\Tools\EvergreenAdmx\EvergreenAdmx.ps1'
    }

    It 'includes powershell host switches and -File path' {
        $taskArgs = New-EvergreenAdmxTaskArgumentList -ScriptPath $script:FakeScript -BoundParameters @{}
        ($taskArgs -join ' ') | Should -Match '-NoProfile'
        ($taskArgs -join ' ') | Should -Match '-ExecutionPolicy Bypass'
        ($taskArgs -join ' ') | Should -Match ([regex]::Escape("-File `"$script:FakeScript`""))
    }

    It 'forwards bound parameters and omits CreateScheduledTask' {
        $bound = [ordered]@{
            WorkingDirectory     = 'C:\Temp\EvergreenAdmx'
            Languages            = @('en-US', 'es', 'fr-FR')
            Include              = @('Microsoft Edge', 'Windows 11')
            UseProductFolders    = [System.Management.Automation.SwitchParameter]::new($true)
            CreateScheduledTask  = [System.Management.Automation.SwitchParameter]::new($true)
        }

        $joined = (New-EvergreenAdmxTaskArgumentList -ScriptPath $script:FakeScript -BoundParameters $bound) -join ' '

        $joined | Should -Match '-WorkingDirectory "C:\\Temp\\EvergreenAdmx"'
        $joined | Should -Match "-Languages @\('en-US','es','fr-FR'\)"
        $joined | Should -Match "-Include @\('Microsoft Edge','Windows 11'\)"
        $joined | Should -Match '-UseProductFolders'
        $joined | Should -Not -Match 'CreateScheduledTask'
    }

    It 'forwards CleanPolicyStore switches' {
        $bound = [ordered]@{
            PolicyStore          = 'C:\PolicyDefinitions'
            CleanPolicyStore     = [System.Management.Automation.SwitchParameter]::new($true)
            CleanPolicyStoreOnly = [System.Management.Automation.SwitchParameter]::new($true)
            CreateScheduledTask  = [System.Management.Automation.SwitchParameter]::new($true)
        }

        $joined = (New-EvergreenAdmxTaskArgumentList -ScriptPath $script:FakeScript -BoundParameters $bound) -join ' '

        $joined | Should -Match '-CleanPolicyStore'
        $joined | Should -Match '-CleanPolicyStoreOnly'
        $joined | Should -Match '-PolicyStore "C:\\PolicyDefinitions"'
        $joined | Should -Not -Match 'CreateScheduledTask'
    }

    It 'escapes single quotes inside array values' {
        $bound = @{
            Include = @("O'Reilly")
        }
        $joined = (New-EvergreenAdmxTaskArgumentList -ScriptPath $script:FakeScript -BoundParameters $bound) -join ' '
        $joined | Should -Match "-Include @\('O''Reilly'\)"
    }
}

Describe 'Include product catalog' {
    BeforeAll {
        $script:Products = Get-EvergreenAdmxIncludeValidateSet
        $script:Catalog = Get-EvergreenAdmxProductCatalog
    }

    It 'includes core products' {
        $script:Products | Should -Contain 'Windows 11'
        $script:Products | Should -Contain 'Microsoft Edge'
        $script:Products | Should -Contain 'HP Anyware'
        $script:Products | Should -Contain 'Custom Policy Store'
        $script:Products | Should -Contain 'Schannel'
        $script:Products | Should -Contain 'Snagit'
    }

    It 'includes all Windows SKUs' {
        @('Windows 10', 'Windows 11', 'Windows 2022', 'Windows 2025') | ForEach-Object {
            $script:Products | Should -Contain $_
        }
    }

    It 'has no duplicate product names' {
        $script:Products.Count | Should -Be ($script:Products | Select-Object -Unique).Count
    }

    It 'has no overlapping aliases across products' {
        $seen = @{}
        foreach ($product in $script:Catalog) {
            $keys = @($product.Name) + @($product.Aliases)
            foreach ($key in $keys) {
                if ([string]::IsNullOrWhiteSpace($key)) { continue }
                $norm = $key.ToLowerInvariant()
                if ($seen.ContainsKey($norm) -and $seen[$norm] -ne $product.Name) {
                    throw "Alias/name '$key' overlaps between '$($seen[$norm])' and '$($product.Name)'."
                }
                $seen[$norm] = $product.Name
            }
        }
        $seen.Count | Should -BeGreaterThan 0
    }
}

Describe 'Resolve-EvergreenAdmxInclude' {
    It 'preserves individual names at the typed script call site for <Scenario>' -ForEach @(
        @{ Scenario = 'one product'; Requested = @('Edge'); Expected = @('Microsoft Edge') }
        @{ Scenario = 'multiple products'; Requested = @('Edge', 'Chrome'); Expected = @('Microsoft Edge', 'Google Chrome') }
        @{ Scenario = 'aliases and duplicates'; Requested = @('Edge', 'Microsoft Edge', 'Chrome'); Expected = @('Microsoft Edge', 'Google Chrome') }
    ) {
        [string[]]$include = @(Resolve-EvergreenAdmxInclude -Include $Requested)
        $include.Count | Should -Be $Expected.Count
        foreach ($product in $Expected) {
            ($include -contains $product) | Should -BeTrue
        }
    }

    It 'preserves every default product at the typed script call site' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$errors)
        $default = ($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Include' }).DefaultValue
        $WindowsVersion = '11'
        $requested = @(& ([scriptblock]::Create($default.Extent.Text)))
        [string[]]$include = @(Resolve-EvergreenAdmxInclude -Include $requested)
        $include.Count | Should -Be $requested.Count
        foreach ($product in $requested) {
            ($include -contains $product) | Should -BeTrue
        }
    }

    It 'preserves every nightly product at the typed script call site' {
        $requested = @(Get-EvergreenAdmxIncludeValidateSet | Where-Object { $_ -notin @('Custom Policy Store', 'Windows 10') })
        [string[]]$include = @(Resolve-EvergreenAdmxInclude -Include $requested)
        $include.Count | Should -Be $requested.Count
        foreach ($product in $requested) {
            ($include -contains $product) | Should -BeTrue
        }
    }

    It 'resolves ProductKey aliases to canonical names' {
        $resolved = Resolve-EvergreenAdmxInclude -Include @('BISF', 'Edge', 'Chrome', 'AVD', 'FSLogix')
        $resolved | Should -Be @('BIS-F', 'Microsoft Edge', 'Google Chrome', 'Microsoft AVD', 'Microsoft FSLogix')
    }

    It 'resolves historical renames' {
        $resolved = Resolve-EvergreenAdmxInclude -Include @('Microsoft Office', 'Azure Virtual Desktop', 'Zoom Desktop Client')
        $resolved | Should -Be @('Microsoft 365 Apps', 'Microsoft AVD', 'Zoom')
    }

    It 'is case-insensitive and deduplicates' {
        $resolved = Resolve-EvergreenAdmxInclude -Include @('bisf', 'BIS-F', 'BisF')
        $resolved | Should -Be @('BIS-F')
    }

    It 'rejects unknown values with a current-product list' {
        $err = { Resolve-EvergreenAdmxInclude -Include @('BISFF') } | Should -Throw -PassThru
        "$err" | Should -Match 'Cannot resolve -Include value'
        "$err" | Should -Match 'BIS-F'
        "$err" | Should -Match 'Microsoft Edge'
        "$err" | Should -Not -Match 'Microsoft Desktop Optimization Pack'
        "$err" | Should -Not -Match '\bMDOP\b'
    }

    It 'rejects removed MDOP with a dedicated message' {
        $err = { Resolve-EvergreenAdmxInclude -Include @('MDOP') } | Should -Throw -PassThru
        "$err" | Should -Match 'no longer supported'
        "$err" | Should -Match 'MDOP'
        "$err" | Should -Not -Match 'Valid products:'
    }

    It 'rejects removed Adobe Classic tracks' {
        $err = { Resolve-EvergreenAdmxInclude -Include @('Adobe Acrobat Classic 2017') } | Should -Throw -PassThru
        "$err" | Should -Match 'no longer supported'
        "$err" | Should -Match 'Adobe Acrobat'
    }
}

Describe 'Snagit release metadata' {
    It 'selects the Snagit zip asset and parses its version' {
        Mock Invoke-RestMethod {
            @{
                tag_name = 'v1.0'
                assets = @(
                    @{ name = 'checksums.txt'; browser_download_url = 'https://example.test/checksums.txt' }
                    @{ name = 'Snagit-ADMX-v1.0.zip'; browser_download_url = 'https://example.test/Snagit-ADMX-v1.0.zip' }
                )
            }
        }
        $release = Get-EvergreenAdmxSnagit
        $release.Version | Should -Be ([version]'1.0')
        $release.URI | Should -Be 'https://example.test/Snagit-ADMX-v1.0.zip'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.github.com/repos/systmworks/ADMX-Snagit/releases/latest'
        }
    }

    It 'rejects releases without the policy zip' {
        Mock Invoke-RestMethod { @{ tag_name = 'v1.0'; assets = @() } }
        { Get-EvergreenAdmxSnagit } | Should -Throw -ExpectedMessage '*no Snagit-ADMX zip asset*'
    }

    It 'resolves the TechSmith alias' {
        Resolve-EvergreenAdmxInclude -Include 'TechSmith Snagit' | Should -Be 'Snagit'
    }
}

Describe 'Snagit template processing' {
    BeforeEach {
        $script:PreviousTemp = $env:TEMP
        $env:TEMP = Join-Path $TestDrive 'temp'
        $script:WorkingDirectory = Join-Path $TestDrive 'work'
        $script:UseProductFolders = $false
        $script:StampAdmxRevision = $false
        $source = Join-Path $TestDrive 'source'
        $language = Join-Path $source 'en-US'
        $null = New-Item $env:TEMP,$language,(Join-Path $script:WorkingDirectory 'downloads') -ItemType Directory -Force
        Set-Content (Join-Path $source 'Snagit.admx') '<policyDefinitions revision="1.0" schemaVersion="1.0"><resources minRequiredRevision="1.0" /></policyDefinitions>'
        Set-Content (Join-Path $language 'Snagit.adml') '<policyDefinitionResources revision="1.0" schemaVersion="1.0" />'
        $script:SnagitZip = Join-Path $TestDrive 'Snagit.zip'
        Compress-Archive -Path (Join-Path $source '*') -DestinationPath $script:SnagitZip -Force
        Mock Get-EvergreenAdmxSnagit { @{ Version = [version]'1.0'; URI = 'https://example.test/Snagit-ADMX-v1.0.zip' } }
        Mock Invoke-FileDownload { Copy-Item -LiteralPath $script:SnagitZip -Destination $OutFile -Force }
    }

    AfterEach {
        $env:TEMP = $script:PreviousTemp
    }

    It 'copies ADMX and en-US ADML and removes temporary extraction files' {
        $release = Invoke-EvergreenAdmxSnagit -Languages @('en-US', 'fr-FR') -WarningAction SilentlyContinue
        $release.Version | Should -Be ([version]'1.0')
        Test-Path (Join-Path $script:WorkingDirectory 'admx/Snagit.admx') | Should -BeTrue
        Test-Path (Join-Path $script:WorkingDirectory 'admx/en-US/Snagit.adml') | Should -BeTrue
        @(Get-ChildItem $env:TEMP -Directory -Filter 'EvergreenAdmx-Snagit-*').Count | Should -Be 0
    }

    It 'uses product folders and stamps revisions when requested' {
        $script:UseProductFolders = $true
        $script:StampAdmxRevision = $true
        Mock Get-EvergreenAdmxSnagit { @{ Version = [version]'2.3'; URI = 'https://example.test/Snagit-ADMX-v2.3.zip' } }
        $null = Invoke-EvergreenAdmxSnagit -Languages 'en-US'
        $file = Join-Path $script:WorkingDirectory 'admx/Snagit/Snagit.admx'
        ([xml](Get-Content $file -Raw)).policyDefinitions.revision | Should -Be '2.3'
    }

    It 'skips a release already processed' {
        Invoke-EvergreenAdmxSnagit -Version '1.0' | Should -BeNullOrEmpty
        Should -Invoke Invoke-FileDownload -Times 0 -Exactly
    }

    It 'fails on incomplete archives and still cleans temporary files' {
        Mock Expand-Archive { $null = New-Item $DestinationPath -ItemType Directory -Force }
        { Invoke-EvergreenAdmxSnagit } | Should -Throw -ExpectedMessage '*must contain Snagit.admx*'
        @(Get-ChildItem $env:TEMP -Directory -Filter 'EvergreenAdmx-Snagit-*').Count | Should -Be 0
    }

    It 'does not report success when copying fails' {
        Mock Copy-Admx { Write-Error 'Template copy failed.' }
        { Invoke-EvergreenAdmxSnagit } | Should -Throw -ExpectedMessage '*Template copy failed*'
        @(Get-ChildItem $env:TEMP -Directory -Filter 'EvergreenAdmx-Snagit-*').Count | Should -Be 0
    }
}

Describe 'Get-EvergreenAdmxObsoleteFilePattern' {
    It 'includes WinStoreUI, Geolocation WLPAdm, legacy Office, Adobe Classic, ctxprofile, and CitrixBase patterns' {
        $patterns = Get-EvergreenAdmxObsoleteFilePattern
        $patterns | Should -Contain 'WinStoreUI.admx'
        $patterns | Should -Contain 'WinStoreUI.adml'
        $patterns | Should -Contain 'Microsoft-Windows-Geolocation-WLPAdm.admx'
        $patterns | Should -Contain 'Microsoft-Windows-Geolocation-WLPAdm.adml'
        $patterns | Should -Contain '*12*.admx'
        $patterns | Should -Contain '*15*.adml'
        $patterns | Should -Contain 'Acrobat2017.admx'
        $patterns | Should -Contain 'AcrobatReader2020.adml'
        $patterns | Should -Contain 'ctxprofile*.admx'
        $patterns | Should -Contain 'CitrixBase.admx'
        $patterns | Should -Contain 'CitrixBase.adml'
    }
}

Describe 'Initialize-PolicyStore' {
    BeforeEach {
        $script:StoreRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("EvergreenAdmx-Store-{0}" -f [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        if ($script:StoreRoot -and (Test-Path -LiteralPath $script:StoreRoot)) {
            Remove-Item -LiteralPath $script:StoreRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates the store and language folders when missing' {
        Initialize-PolicyStore -PolicyStore $script:StoreRoot -Languages @('en-US', 'fr-FR')
        Test-Path -LiteralPath $script:StoreRoot | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'en-US') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'fr-FR') | Should -BeTrue
    }

    It 'supports -WhatIf without creating folders' {
        Initialize-PolicyStore -PolicyStore $script:StoreRoot -Languages @('en-US') -WhatIf
        Test-Path -LiteralPath $script:StoreRoot | Should -BeFalse
    }
}

Describe 'Clear-ObsoleteAdmx' {
    BeforeEach {
        $script:StoreRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("EvergreenAdmx-Clean-{0}" -f [guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $script:StoreRoot -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $script:StoreRoot 'en-US') -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $script:StoreRoot 'fr-FR') -ItemType Directory -Force

        # Keep
        Set-Content -Path (Join-Path $script:StoreRoot 'windows.admx') -Value 'keep'
        Set-Content -Path (Join-Path $script:StoreRoot 'en-US\windows.adml') -Value 'keep'
        Set-Content -Path (Join-Path $script:StoreRoot 'office16.admx') -Value 'keep'
        Set-Content -Path (Join-Path $script:StoreRoot 'en-US\office16.adml') -Value 'keep'
        Set-Content -Path (Join-Path $script:StoreRoot 'LocationProviderAdm.admx') -Value 'keep'
        Set-Content -Path (Join-Path $script:StoreRoot 'en-US\LocationProviderAdm.adml') -Value 'keep'

        # Obsolete
        Set-Content -Path (Join-Path $script:StoreRoot 'WinStoreUI.admx') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'en-US\WinStoreUI.adml') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'Microsoft-Windows-Geolocation-WLPAdm.admx') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'en-US\Microsoft-Windows-Geolocation-WLPAdm.adml') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'excel15.admx') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'en-US\excel15.adml') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'Acrobat2017.admx') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'AcrobatReader2020.admx') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'ctxprofile7.admx') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'CitrixBase.admx') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'en-US\CitrixBase.adml') -Value 'remove'
        Set-Content -Path (Join-Path $script:StoreRoot 'readme.txt') -Value 'junk'
        $null = New-Item -Path (Join-Path $script:StoreRoot 'extract-debris') -ItemType Directory -Force
        Set-Content -Path (Join-Path $script:StoreRoot 'extract-debris\file.txt') -Value 'junk'
    }

    AfterEach {
        if ($script:StoreRoot -and (Test-Path -LiteralPath $script:StoreRoot)) {
            Remove-Item -LiteralPath $script:StoreRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'removes obsolete Admx/Adml, non-policy files, and non-language folders' {
        $removed = Clear-ObsoleteAdmx -PolicyStore $script:StoreRoot -Languages @('en-US', 'fr-FR')

        $removed.Count | Should -BeGreaterThan 0
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'WinStoreUI.admx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'en-US\WinStoreUI.adml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'Microsoft-Windows-Geolocation-WLPAdm.admx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'en-US\Microsoft-Windows-Geolocation-WLPAdm.adml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'excel15.admx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'Acrobat2017.admx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'AcrobatReader2020.admx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'ctxprofile7.admx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'CitrixBase.admx') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'en-US\CitrixBase.adml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'readme.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'extract-debris') | Should -BeFalse

        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'windows.admx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'office16.admx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'LocationProviderAdm.admx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'en-US') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'fr-FR') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'en-US\windows.adml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'fr-FR\windows.adml') | Should -BeTrue
    }

    It 'copies missing language ADMLs from en-US' {
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'fr-FR\windows.adml') | Should -BeFalse
        $null = Clear-ObsoleteAdmx -PolicyStore $script:StoreRoot -Languages @('en-US', 'fr-FR')
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'fr-FR\windows.adml') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $script:StoreRoot 'fr-FR\windows.adml') -Raw).Trim() | Should -Be 'keep'
    }

    It 'supports -WhatIf without deleting files or copying ADMLs' {
        $null = Clear-ObsoleteAdmx -PolicyStore $script:StoreRoot -Languages @('en-US', 'fr-FR') -WhatIf

        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'WinStoreUI.admx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'Microsoft-Windows-Geolocation-WLPAdm.admx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'readme.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'extract-debris') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'windows.admx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:StoreRoot 'fr-FR\windows.adml') | Should -BeFalse
    }

}


Describe 'ADMX revision stamping' {
    It 'converts <SourceVersion> to <Expected>' -ForEach @(
        @{ SourceVersion = '143.0.3624.0'; Expected = '143.0' }
        @{ SourceVersion = '0.95.1'; Expected = '0.95' }
        @{ SourceVersion = '1.2'; Expected = '1.2' }
        @{ SourceVersion = '108542.1.0'; Expected = '108542.1' }
        @{ SourceVersion = 'v1.17.0'; Expected = '1.17' }
    ) {
        ConvertTo-AdmxRevisionString -Version $SourceVersion | Should -Be $Expected
    }

    It 'returns null for non-parseable versions' {
        ConvertTo-AdmxRevisionString -Version 'not-a-version' -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'stamps only revision 1.0 attributes and leaves higher revisions alone' {
        $root = Join-Path -Path $TestDrive -ChildPath 'admxrev'
        $lang = Join-Path -Path $root -ChildPath 'en-US'
        $null = New-Item -Path $lang -ItemType Directory -Force

        $admxOne = '<?xml version="1.0" encoding="utf-8"?><policyDefinitions revision="1.0" schemaVersion="1.0"><policyNamespaces><target prefix="demo" namespace="Demo.Policies" /></policyNamespaces><resources minRequiredRevision="1.0" /></policyDefinitions>'
        $admxHigh = '<?xml version="1.0" encoding="utf-8"?><policyDefinitions revision="4.8" schemaVersion="1.0"><policyNamespaces><target prefix="parent" namespace="Parent.Policies" /></policyNamespaces><resources minRequiredRevision="4.8" /></policyDefinitions>'
        $admlOne = '<?xml version="1.0" encoding="utf-8"?><policyDefinitionResources revision="1.0" schemaVersion="1.0"><displayName>Demo</displayName><resources /></policyDefinitionResources>'
        $admlHigh = '<?xml version="1.0" encoding="utf-8"?><policyDefinitionResources revision="1.20" schemaVersion="1.0"><displayName>Parent</displayName><resources /></policyDefinitionResources>'

        Set-Content -LiteralPath (Join-Path $root 'demo.admx') -Value $admxOne -Encoding utf8
        Set-Content -LiteralPath (Join-Path $root 'parent.admx') -Value $admxHigh -Encoding utf8
        Set-Content -LiteralPath (Join-Path $lang 'demo.adml') -Value $admlOne -Encoding utf8
        Set-Content -LiteralPath (Join-Path $lang 'parent.adml') -Value $admlHigh -Encoding utf8

        Set-AdmxRevision -Path $root -Revision '143.0'

        ([xml](Get-Content -LiteralPath (Join-Path $root 'demo.admx') -Raw)).policyDefinitions.revision | Should -Be '143.0'
        ([xml](Get-Content -LiteralPath (Join-Path $root 'demo.admx') -Raw)).policyDefinitions.resources.minRequiredRevision | Should -Be '143.0'
        ([xml](Get-Content -LiteralPath (Join-Path $lang 'demo.adml') -Raw)).policyDefinitionResources.revision | Should -Be '143.0'
        ([xml](Get-Content -LiteralPath (Join-Path $root 'parent.admx') -Raw)).policyDefinitions.revision | Should -Be '4.8'
        ([xml](Get-Content -LiteralPath (Join-Path $lang 'parent.adml') -Raw)).policyDefinitionResources.revision | Should -Be '1.20'
    }
}

