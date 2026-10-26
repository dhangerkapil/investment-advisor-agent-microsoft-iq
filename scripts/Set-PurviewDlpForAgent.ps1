<#
.SYNOPSIS
    Creates (or removes) the Microsoft Purview DLP policy that the agent's Purview middleware enforces: prompts to the
    agent that contain a sensitive information type are blocked, and each match raises a DLP alert.

.DESCRIPTION
    The policy is scoped to the hosted agent's Entra agent identity, an "Entra-registered AI app" in Purview terms, with
    the Application enforcement plane. Its rule blocks UploadText (the user's prompt) that contains the sensitive
    information type, and raises an alert that shows in Purview's DLP alerts and in Microsoft Defender XDR.

    Prerequisites:
    - enable_purview = true in terraform.tfvars (Deploy-AdvisorDemo.ps1 -EnablePurview), then the Agent step: the
      agent's Purview middleware and its three Microsoft Graph roles;
    - Microsoft Purview pay-as-you-go billing in the tenant (Purview portal > Settings > Account);
    - the ExchangeOnlineManagement module and a Compliance Administrator (or Global Administrator) account.

    Policies reach the service within about an hour. The policy and rule names differ from the multi-agent sample's,
    so both can live in one tenant (DLP rule names are unique per tenant).

.EXAMPLE
    .\scripts\Set-PurviewDlpForAgent.ps1 -UserPrincipalName admin@contoso.onmicrosoft.com
    .\scripts\Set-PurviewDlpForAgent.ps1 -UserPrincipalName admin@contoso.onmicrosoft.com -DisableWAM   # sign in in the browser
    .\scripts\Set-PurviewDlpForAgent.ps1 -UserPrincipalName admin@contoso.onmicrosoft.com -Remove
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserPrincipalName,
    # The hosted agent's Entra agent identity (its app ID equals its object ID); default: Terraform's agent_principal_id.
    [string]$AgentAppId,
    # How the agent is named in the policy's location; default: Terraform's agent_name.
    [string]$AgentDisplayName,
    [string]$PolicyName = 'Investment Advisor agent: block sensitive data in prompts',
    [string]$RuleName = 'Investment Advisor agent: block U.S. Social Security numbers in prompts',
    [string]$SensitiveInformationType = 'U.S. Social Security Number (SSN)',
    # A Security & Compliance PowerShell token, for automation; otherwise the sign-in is interactive.
    [string]$AccessToken,
    # Sign in in the browser instead of the Windows account dialog, where that fails ("A window handle must be
    # configured", for example in a host without a console window).
    [switch]$DisableWAM,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable ExchangeOnlineManagement)) {
    throw 'Install the ExchangeOnlineManagement module first: Install-Module ExchangeOnlineManagement -Scope CurrentUser'
}
Import-Module ExchangeOnlineManagement

if (-not $Remove -and (-not $AgentAppId -or -not $AgentDisplayName)) {
    . "$PSScriptRoot\Use-IsolatedAzure.ps1"
    $tf = Join-Path (Split-Path $PSScriptRoot -Parent) 'terraform'
    if (-not $AgentAppId) { $AgentAppId = (terraform "-chdir=$tf" output -raw -no-color agent_principal_id).Trim() }
    if (-not $AgentDisplayName) {
        $name = (terraform "-chdir=$tf" output -raw -no-color agent_name 2>$null)
        $AgentDisplayName = if ($name) { "$($name.Trim()) (Investment Advisor)" } else { 'Investment Advisor agent' }
    }
}
if (-not $Remove -and $AgentAppId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw "No agent identity: release the agent first (-Step Agent), or pass -AgentAppId. Got '$AgentAppId'."
}

$connect = @{ UserPrincipalName = $UserPrincipalName; ShowBanner = $false }
if ($AccessToken) { $connect.AccessToken = $AccessToken }
if ($DisableWAM) { $connect.DisableWAM = $true }
Connect-IPPSSession @connect
try {
    $policy = Get-DlpCompliancePolicy -Identity $PolicyName -ErrorAction SilentlyContinue
    if ($Remove) {
        if ($policy) {
            Get-DlpComplianceRule -Policy $PolicyName | ForEach-Object { Remove-DlpComplianceRule -Identity $_.Name -Confirm:$false }
            Remove-DlpCompliancePolicy -Identity $PolicyName -Confirm:$false
            Write-Output "Removed the DLP policy '$PolicyName'."
        } else {
            Write-Output "No DLP policy named '$PolicyName'."
        }
        return
    }

    if (-not $policy) {
        $location = @(@{
                Workload            = 'Applications'
                Location            = $AgentAppId
                LocationDisplayName = $AgentDisplayName
                LocationSource      = 'Entra'
                LocationType        = 'Individual'
                Inclusions          = @(@{ Type = 'Tenant'; Identity = 'All' })
            }) | ConvertTo-Json -Depth 5 -Compress -AsArray
        $policy = New-DlpCompliancePolicy -Name $PolicyName -Mode Enable -Locations $location -EnforcementPlanes @('Application') `
            -Comment 'Blocks prompts with sensitive data before the Investment Advisor agent sees them (the agent calls Purview through Agent Framework).'
        Write-Output "Created the DLP policy '$PolicyName' for the Entra app $AgentAppId."
    } else {
        Write-Output "The DLP policy '$PolicyName' exists."
    }

    if (-not (Get-DlpComplianceRule -Policy $PolicyName | Where-Object Name -EQ $RuleName)) {
        New-DlpComplianceRule -Name $RuleName -Policy $PolicyName `
            -ContentContainsSensitiveInformation @{ Name = $SensitiveInformationType } `
            -RestrictAccess @(@{ setting = 'UploadText'; value = 'Block' }) `
            -GenerateAlert $true -ReportSeverityLevel 'Medium' | Out-Null
        Write-Output "Created the rule '$RuleName': block prompts that contain '$SensitiveInformationType', with an alert."
    } else {
        Write-Output "The rule '$RuleName' exists."
    }

    Get-DlpCompliancePolicy -Identity $PolicyName | Select-Object Name, Mode, EnforcementPlanes, DistributionStatus |
        Format-List | Out-String | Write-Output
} finally {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}
