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
$script:DSCResourceName = 'SPWebAppThrottlingSettings'
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

                # Initialize tests

                # Mocks for all contexts
                Mock -CommandName New-SPAuthenticationProvider -MockWith { }
                Mock -CommandName New-SPWebApplication -MockWith { }
                Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                    return @{
                        DisableKerberos = $true
                        AllowAnonymous  = $false
                    }
                }
            }

            # Test contexts
            Context -Name "The web appliation exists and has the correct throttling settings" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl                 = "http://sites.sharepoint.com"
                        ListViewThreshold         = 1000
                        AllowObjectModelOverride  = $true
                        AdminThreshold            = 2000
                        ListViewLookupThreshold   = 12
                        HappyHourEnabled          = $true
                        HappyHour                 = (New-CimInstance -ClassName MSFT_SPWebApplicationHappyHour -Property @{
                                Hour     = 2
                                Minute   = 0
                                Duration = 1
                            } -ClientOnly)
                        UniquePermissionThreshold = 100
                        RequestThrottling         = $true
                        ChangeLogEnabled          = $true
                        ChangeLogExpiryDays       = 30
                        EventHandlersEnabled      = $true
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        return @(@{
                                DisplayName                                     = $testParams.Name
                                ApplicationPool                                 = @{
                                    Name     = $testParams.ApplicationPool
                                    Username = $testParams.ApplicationPoolAccount
                                }
                                ContentDatabases                                = @(
                                    @{
                                        Name   = "SP_Content_01"
                                        Server = "sql.domain.local"
                                    }
                                )
                                IisSettings                                     = @(
                                    @{ Path = "C:\inetpub\wwwroot\something" }
                                )
                                Url                                             = $testParams.WebAppUrl
                                MaxItemsPerThrottledOperation                   = $testParams.ListViewThreshold
                                AllowOMCodeOverrideThrottleSettings             = $testParams.AllowObjectModelOverride
                                MaxItemsPerThrottledOperationOverride           = $testParams.AdminThreshold
                                MaxQueryLookupFields                            = $testParams.ListViewLookupThreshold
                                UnthrottledPrivilegedOperationWindowEnabled     = $testParams.HappyHourEnabled
                                DailyStartUnthrottledPrivilegedOperationsHour   = $testParams.HappyHour.Hour
                                DailyStartUnthrottledPrivilegedOperationsMinute = $testParams.HappyHour.Minute
                                DailyUnthrottledPrivilegedOperationsDuration    = $testParams.HappyHour.Duration
                                MaxUniquePermScopesPerList                      = $testParams.UniquePermissionThreshold
                                HttpThrottleSettings                            = @{
                                    PerformThrottle = $testParams.RequestThrottling
                                }
                                ChangeLogExpirationEnabled                      = $testParams.ChangeLogEnabled
                                ChangeLogRetentionPeriod                        = @{
                                    Days = $testParams.ChangeLogExpiryDays
                                }
                                EventHandlersEnabled                            = $testParams.EventHandlersEnabled
                            })
                    }
                }

                It "Should return the current data from the get method" {
                    (Get-TargetResource @testParams).ListViewThreshold | Should -Be $testParams.ListViewThreshold
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The web appliation exists and uses incorrect throttling settings" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl                 = "http://sites.sharepoint.com"
                        ListViewThreshold         = 1000
                        AllowObjectModelOverride  = $true
                        AdminThreshold            = 2000
                        ListViewLookupThreshold   = 12
                        HappyHourEnabled          = $true
                        HappyHour                 = (New-CimInstance -ClassName MSFT_SPWebApplicationHappyHour -Property @{
                                Hour     = 2
                                Minute   = 0
                                Duration = 1
                            } -ClientOnly)
                        UniquePermissionThreshold = 100
                        RequestThrottling         = $true
                        ChangeLogEnabled          = $true
                        ChangeLogExpiryDays       = 30
                        EventHandlersEnabled      = $true
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $httpThrottle = @{
                            PerformThrottle = $testParams.RequestThrottling
                        }
                        $httpThrottle = $httpThrottle | Add-Member -MemberType ScriptMethod -Name Update -Value {
                            return $null
                        } -PassThru

                        $webApp = @{
                            DisplayName                                     = $testParams.Name
                            ApplicationPool                                 = @{
                                Name     = $testParams.ApplicationPool
                                Username = $testParams.ApplicationPoolAccount
                            }
                            ContentDatabases                                = @(
                                @{
                                    Name   = "SP_Content_01"
                                    Server = "sql.domain.local"
                                }
                            )
                            IisSettings                                     = @(
                                @{ Path = "C:\inetpub\wwwroot\something" }
                            )
                            Url                                             = $testParams.WebAppUrl
                            MaxItemsPerThrottledOperation                   = 1
                            AllowOMCodeOverrideThrottleSettings             = $testParams.AllowObjectModelOverride
                            MaxItemsPerThrottledOperationOverride           = $testParams.AdminThreshold
                            MaxQueryLookupFields                            = $testParams.ListViewLookupThreshold
                            UnthrottledPrivilegedOperationWindowEnabled     = $testParams.HappyHourEnabled
                            DailyStartUnthrottledPrivilegedOperationsHour   = $testParams.HappyHour.Hour
                            DailyStartUnthrottledPrivilegedOperationsMinute = $testParams.HappyHour.Minute
                            DailyUnthrottledPrivilegedOperationsDuration    = $testParams.HappyHour.Duration
                            MaxUniquePermScopesPerList                      = $testParams.UniquePermissionThreshold
                            HttpThrottleSettings                            = $httpThrottle
                            ChangeLogExpirationEnabled                      = $testParams.ChangeLogEnabled
                            ChangeLogRetentionPeriod                        = @{
                                Days = $testParams.ChangeLogExpiryDays
                            }
                            EventHandlersEnabled                            = $testParams.EventHandlersEnabled
                        }
                        $webApp = $webApp | Add-Member -MemberType ScriptMethod -Name Update -Value {
                            $Global:SPDscWebApplicationUpdateCalled = $true
                        } -PassThru | Add-Member -MemberType ScriptMethod SetDailyUnthrottledPrivilegedOperationWindow {
                            $Global:SPDscWebApplicationUpdateHappyHourCalled = $true
                        } -PassThru
                        return @($webApp)
                    }
                }

                It "Should return the current data from the get method" {
                    (Get-TargetResource @testParams).ListViewThreshold | Should -Be 1
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update the throttling settings" {
                    $Global:SPDscWebApplicationUpdateCalled = $false
                    $Global:SPDscWebApplicationUpdateHappyHourCalled = $false
                    Set-TargetResource @testParams
                    $Global:SPDscWebApplicationUpdateCalled | Should -Be $true
                }

                It "Should update the incorrect happy hour settings" {
                    $testParams = @{
                        WebAppUrl                 = "http://sites.sharepoint.com"
                        ListViewThreshold         = 1000
                        AllowObjectModelOverride  = $true
                        AdminThreshold            = 2000
                        ListViewLookupThreshold   = 12
                        HappyHourEnabled          = $true
                        HappyHour                 = (New-CimInstance -ClassName MSFT_SPWebApplicationHappyHour -Property @{
                                Hour     = 5
                                Minute   = 0
                                Duration = 1
                            } -ClientOnly)
                        UniquePermissionThreshold = 100
                        RequestThrottling         = $true
                        ChangeLogEnabled          = $true
                        ChangeLogExpiryDays       = 30
                        EventHandlersEnabled      = $true
                    }
                    $Global:SPDscWebApplicationUpdateCalled = $false
                    $Global:SPDscWebApplicationUpdateHappyHourCalled = $false

                    Set-TargetResource @testParams
                    $Global:SPDscWebApplicationUpdateCalled | Should -Be $true
                    $Global:SPDscWebApplicationUpdateHappyHourCalled | Should -Be $true
                }

                It "Should throw exceptions where invalid happy hour settings are provided" {
                    $testParams = @{
                        Name                   = "SharePoint Sites"
                        ApplicationPool        = "SharePoint Web Apps"
                        ApplicationPoolAccount = "DEMO\ServiceAccount"
                        WebAppUrl              = "http://sites.sharepoint.com"
                        AuthenticationMethod   = "NTLM"
                        ThrottlingSettings     = (New-CimInstance -ClassName MSFT_SPWebApplicationThrottling -Property @{
                                HappyHourEnabled = $true
                                HappyHour        = (New-CimInstance -ClassName MSFT_SPWebApplicationHappyHour -Property @{
                                        Hour     = 100
                                        Minute   = 0
                                        Duration = 1
                                    } -ClientOnly)
                            } -ClientOnly)
                    }
                    { Set-TargetResource @testParams } | Should -Throw

                    $testParams = @{
                        Name                   = "SharePoint Sites"
                        ApplicationPool        = "SharePoint Web Apps"
                        ApplicationPoolAccount = "DEMO\ServiceAccount"
                        WebAppUrl              = "http://sites.sharepoint.com"
                        AuthenticationMethod   = "NTLM"
                        ThrottlingSettings     = (New-CimInstance -ClassName MSFT_SPWebApplicationThrottling -Property @{
                                HappyHourEnabled = $true
                                HappyHour        = (New-CimInstance -ClassName MSFT_SPWebApplicationHappyHour -Property @{
                                        Hour     = 5
                                        Minute   = 100
                                        Duration = 1
                                    } -ClientOnly)
                            } -ClientOnly)
                    }
                    { Set-TargetResource @testParams } | Should -Throw

                    $testParams = @{
                        Name                   = "SharePoint Sites"
                        ApplicationPool        = "SharePoint Web Apps"
                        ApplicationPoolAccount = "DEMO\ServiceAccount"
                        WebAppUrl              = "http://sites.sharepoint.com"
                        AuthenticationMethod   = "NTLM"
                        ThrottlingSettings     = (New-CimInstance -ClassName MSFT_SPWebApplicationThrottling -Property @{
                                HappyHourEnabled = $true
                                HappyHour        = (New-CimInstance -ClassName MSFT_SPWebApplicationHappyHour -Property @{
                                        Hour     = 5
                                        Minute   = 0
                                        Duration = 100
                                    } -ClientOnly)
                            } -ClientOnly)
                    }
                    { Set-TargetResource @testParams } | Should -Throw
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
