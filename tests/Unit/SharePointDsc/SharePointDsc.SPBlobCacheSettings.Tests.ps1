[CmdletBinding()]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPBlobCacheSettings'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Initialize the tests
                $relativePath = "\inetpub\wwwroot\Virtual Directories\8080"
                $Global:SPDscWebConfigPath = Join-Path -Path "TestDrive:\" -ChildPath $relativePath
                $Global:SPDscWebConfigRealPath = Join-Path -Path $TestDrive.FullName -ChildPath $relativePath
                $Global:SPDscWebConfigFile = Join-Path -Path $Global:SPDscWebConfigPath -ChildPath "web.config"
                New-Item -Path $Global:SPDscWebConfigPath -ItemType Directory

                try
                {
                    [Microsoft.SharePoint.Administration.SPUrlZone]
                }
                catch
                {
                    Add-Type -TypeDefinition @"
    namespace Microsoft.SharePoint.Administration {
        public enum SPUrlZone { Default, Intranet, Internet, Custom, Extranet };
    }
"@
                }

                # Mocks for all contexts
                Mock -CommandName Get-SPWebApplication -MockWith {
                    return @{
                        IISSettings = @(@{
                                Path = $Global:SPDscWebConfigRealPath
                            })
                    }
                }

                Mock -CommandName Get-SPServiceInstance -MockWith {
                    return @(
                        @{
                            Name     = ""
                            TypeName = "Microsoft SharePoint Foundation Web Application"
                        } | Add-Member -MemberType ScriptMethod `
                            -Name GetType `
                            -Value {
                            return @{
                                Name = "SPWebServiceInstance"
                            }
                        } -PassThru -Force | Add-Member -Name Name `
                            -MemberType ScriptProperty `
                            -PassThru `
                        {
                            # get
                            ""
                        }`
                        {
                            # set
                            param ( $arg )
                        }
                    )
                }

                function Update-SPDscTestConfigFile
                {
                    [CmdletBinding()]
                    param(
                        [Parameter(Mandatory = $true)]
                        [String]
                        $Content
                    )
                    Set-Content -Path $Global:SPDscWebConfigFile -Value $Content
                }
            }

            # Test contexts
            Context -Name "The web application doesn't exist" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http://sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $true
                        Location    = "c:\BlobCache"
                        MaxSizeInGB = 30
                        FileTypes   = "\.(gif|jpg|jpeg)$"
                    }

                    Mock -CommandName Get-SPWebApplication -MockWith { return $null }
                    Mock -CommandName Test-Path -MockWith { return $false }
                }

                It "Should throw exception from the get method" {
                    (Get-TargetResource @testParams).WebAppUrl | Should -Be $null
                }

                It "Should throw exception from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw exception from the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Specified web application could not be found."
                }
            }

            Context -Name "BlobCache is enabled, but the MaxSize parameters cannot be converted to Uint16" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http://sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $true
                        Location    = "c:\BlobCache"
                        MaxSizeInGB = 30
                        FileTypes   = "\.(gif|jpg|jpeg)$"
                    }

                    Update-SPDscTestConfigFile -Content '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <configuration>
        <SharePoint>
            <BlobCache location="c:\BlobCache" path="\.(gif|jpg|jpeg)$" maxSize="30x" enabled="True" />
        </SharePoint>
        </configuration>'

                    Mock -CommandName Test-Path -MockWith { return $true }

                    Mock -CommandName Copy-Item -MockWith { }
                }

                It "Should return 0 from the get method" {
                    (Get-TargetResource @testParams).MaxSizeInGB | Should -Be 0
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should return MaxSize 30 in web.config from the set method" {
                    Set-TargetResource @testParams
                    [xml] $webcfg = Get-Content -Path $Global:SPDscWebConfigFile
                    $webcfg.configuration.SharePoint.BlobCache.maxsize | Should -Be "30"
                }
            }

            Context -Name "BlobCache correctly configured, but the folder does not exist" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http://sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $true
                        Location    = "c:\BlobCache"
                        MaxSizeInGB = 30
                        FileTypes   = "\.(gif|jpg|jpeg)$"
                    }

                    Update-SPDscTestConfigFile -Content '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <configuration>
        <SharePoint>
            <BlobCache location="c:\BlobCache" path="\.(gif|jpg|jpeg)$" maxSize="30" enabled="True" />
        </SharePoint>
        </configuration>'

                    Mock -CommandName Test-Path -MockWith { return $false }
                    Mock -CommandName New-Item -MockWith { }

                    Mock -CommandName Copy-Item -MockWith { }
                }

                It "Should return values from the get method" {
                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should check if function is called in the set method" {
                    Set-TargetResource @testParams
                }
            }

            Context -Name "BlobCache is enabled, but the other parameters do not match" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http://sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $true
                        Location    = "c:\BlobCache"
                        MaxSizeInGB = 30
                        MaxAge      = 30
                        FileTypes   = "\.(gif|jpg|jpeg)$"
                    }


                    Update-SPDscTestConfigFile -Content '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <configuration>
        <SharePoint>
            <BlobCache location="c:\BlobCache" path="\.(csv|gif|jpg|jpeg)$" maxSize="20" enabled="True" />
        </SharePoint>
        </configuration>'

                    Mock -CommandName Test-Path -MockWith { return $true }

                    Mock -CommandName Copy-Item -MockWith { }
                }

                It "Should return values from the get method" {
                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should return MaxSize 30 from the set method" {
                    Set-TargetResource @testParams
                    [xml] $webcfg = Get-Content -Path $Global:SPDscWebConfigFile
                    $webcfg.configuration.SharePoint.BlobCache.maxsize | Should -Be "30"
                    $webcfg.configuration.SharePoint.BlobCache."max-age" | Should -Be "30"
                }
            }

            Context -Name "BlobCache is disabled, but the parameters specify it to be enabled" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http://sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $true
                        Location    = "c:\BlobCache"
                        MaxSizeInGB = 30
                        FileTypes   = "\.(gif|jpg|jpeg)$"
                    }

                    Update-SPDscTestConfigFile -Content '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <configuration>
        <SharePoint>
            <BlobCache location="c:\BlobCache" path="\.(gif|jpg|jpeg)$" maxSize="20" enabled="False" />
        </SharePoint>
        </configuration>'

                    Mock -CommandName Get-SPWebApplication -MockWith {
                        $IISSettings = @(@{
                                Path = $Global:SPDscWebConfigRealPath
                            })
                        $iisSettingsCol = { $IISSettings }.Invoke()


                        $webapp = @{
                            IISSettings = $iisSettingsCol
                        }

                        return $webapp
                    }

                    Mock -CommandName Test-Path -MockWith { return $true }

                    Mock -CommandName Copy-Item -MockWith { }
                }

                It "Should return values from the get method" {
                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should return Enabled False from the set method" {
                    Set-TargetResource @testParams
                    [xml] $webcfg = Get-Content -Path $Global:SPDscWebConfigFile
                    $webcfg.configuration.SharePoint.BlobCache.enabled | Should -Be "True"
                }
            }

            Context -Name "The specified configuration is correctly configured" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http://sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $true
                        Location    = "c:\BlobCache"
                        MaxSizeInGB = 30
                        FileTypes   = "\.(gif|jpg|jpeg)$"
                    }

                    Update-SPDscTestConfigFile -Content '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <configuration>
        <SharePoint>
            <BlobCache location="c:\BlobCache" path="\.(gif|jpg|jpeg)$" maxSize="30" enabled="True" />
        </SharePoint>
        </configuration>'

                    Mock -CommandName Test-Path -MockWith { return $true }
                }

                It "Should return values from the get method" {
                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "BlobCache is enabled, but the parameters specify it to be disabled" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http:/sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $false
                    }

                    Update-SPDscTestConfigFile -Content '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <configuration>
        <SharePoint>
            <BlobCache location="c:\BlobCache" path="\.(gif|jpg|jpeg)$" maxSize="30" enabled="True" />
        </SharePoint>
        </configuration>'

                    Mock -CommandName Test-Path -MockWith { return $true }

                    Mock -CommandName Copy-Item -MockWith { }
                }

                It "Should return values from the get method" {
                    Get-TargetResource @testParams | Should -Not -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should return correct values in the config file after the set method" {
                    Set-TargetResource @testParams
                    [xml] $webcfg = Get-Content -Path $Global:SPDscWebConfigFile
                    $webcfg.configuration.SharePoint.BlobCache.enabled | Should -Be "False"
                }
            }

            Context -Name "The server doesn't have the web application role running" {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl   = "http://sharepoint.contoso.com"
                        Zone        = "Default"
                        EnableCache = $true
                        Location    = "c:\BlobCache"
                        MaxSizeInGB = 30
                        FileTypes   = "\.(gif|jpg|jpeg)$"
                    }

                    Update-SPDscTestConfigFile -Content '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <configuration>
        <SharePoint>
            <BlobCache location="c:\BlobCache" path="\.(gif|jpg|jpeg)$" maxSize="30" enabled="True" />
        </SharePoint>
        </configuration>'

                    Mock -CommandName Test-Path -MockWith { return $true }
                    Mock -CommandName Get-SPServiceInstance -MockWith {
                        return @(
                            $null | Add-Member -MemberType ScriptMethod `
                                -Name GetType `
                                -Value {
                                return @{
                                    Name = "SPWebServiceInstance"
                                }
                            } -PassThru -Force | Add-Member -Name Name `
                                -MemberType ScriptProperty `
                                -PassThru `
                            {
                                # get
                                ""
                            }`
                            {
                                # set
                                param ( $arg )
                            }
                        )
                    }
                }

                It "Should return values from the get method" {
                    (Get-TargetResource @testParams).WebAppUrl | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw exception in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Server isn't running the Web Application role"
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
