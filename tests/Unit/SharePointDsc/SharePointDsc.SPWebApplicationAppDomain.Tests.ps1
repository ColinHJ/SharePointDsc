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
$script:DSCResourceName = 'SPWebApplicationAppDomain'
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
                Mock -CommandName New-SPWebApplicationAppDomain -MockWith { }
                Mock -CommandName Remove-SPWebApplicationAppDomain -MockWith { }
                Mock -CommandName Start-Sleep -MockWith { }
            }

            # Test contexts
            Context -Name "No app domain settings have been configured for the specified web app and zone" -Fixture {
                BeforeAll {
                    $testParams = @{
                        AppDomain = "contosointranetapps.com"
                        WebAppUrl = "http://portal.contoso.com"
                        Zone      = "Default"
                        Port      = 80;
                        SSL       = $false
                    }

                    Mock -CommandName Get-SPWebApplicationAppDomain -MockWith { return $null }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).AppDomain | Should -BeNullOrEmpty
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should create the new app domain entry" {
                    Set-TargetResource @testParams
                    Assert-MockCalled New-SPWebApplicationAppDomain
                }
            }

            Context -Name "An app domain has been configured for the specified web app and zone but it's not correct" -Fixture {
                BeforeAll {
                    $testParams = @{
                        AppDomain = "contosointranetapps.com"
                        WebAppUrl = "http://portal.contoso.com"
                        Zone      = "Default"
                        Port      = 80;
                        SSL       = $false
                    }

                    Mock -CommandName Get-SPWebApplicationAppDomain -MockWith {
                        return @{
                            AppDomain   = "wrong.domain"
                            UrlZone     = $testParams.Zone
                            Port        = $testParams.Port
                            IsSchemeSSL = $testParams.SSL
                        }
                    }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).AppDomain | Should -Be "wrong.domain"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should create the new app domain entry" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPWebApplicationAppDomain
                    Assert-MockCalled New-SPWebApplicationAppDomain
                }
            }

            Context -Name "The correct app domain has been configued for the requested web app and zone" -Fixture {
                BeforeAll {
                    $testParams = @{
                        AppDomain = "contosointranetapps.com"
                        WebAppUrl = "http://portal.contoso.com"
                        Zone      = "Default"
                        Port      = 80;
                        SSL       = $false
                    }

                    Mock -CommandName Get-SPWebApplicationAppDomain -MockWith {
                        return @{
                            AppDomain   = $testParams.AppDomain
                            UrlZone     = $testParams.Zone
                            Port        = $testParams.Port
                            IsSchemeSSL = $testParams.SSL
                        }
                    }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).AppDomain | Should -Be $testParams.AppDomain
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The functions operate without optional parameters included" -Fixture {
                BeforeAll {
                    $testParams = @{
                        AppDomain = "contosointranetapps.com"
                        WebAppUrl = "http://portal.contoso.com"
                        Zone      = "Default"
                    }

                    Mock -CommandName Get-SPWebApplicationAppDomain -MockWith {
                        return @{
                            AppDomain   = "invalid.domain"
                            UrlZone     = $testParams.Zone
                            Port        = $testParams.Port
                            IsSchemeSSL = $testParams.SSL
                        }
                    }
                }

                It "Should return null from the get method" {
                    (Get-TargetResource @testParams).AppDomain | Should -Be "invalid.domain"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should create the new app domain entry" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPWebApplicationAppDomain
                    Assert-MockCalled New-SPWebApplicationAppDomain
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
