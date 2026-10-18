<#
.SYNOPSIS
    Signs the isolated profile in to the tenant named in .env.local by device code.

.DESCRIPTION
    Open https://microsoft.com/devicelogin in a browser window that is already
    signed in as the intended account (for example a private window), and enter
    the printed code. The default Azure CLI profile is not touched.
#>
. "$PSScriptRoot\Use-IsolatedAzure.ps1"
if (-not $env:ARM_TENANT_ID) { throw 'AZURE_TENANT_ID is missing from .env.local.' }

az config set core.enable_broker_on_windows=false core.login_experience_v2=off core.collect_telemetry=false --only-show-errors
# Start from an empty token cache: after a Conditional Access change, Continuous Access Evaluation rejects cached
# access tokens (TokenCreatedWithOutdatedPolicies) that a new sign-in alone would not replace.
az account clear --only-show-errors
az login --tenant $env:ARM_TENANT_ID --use-device-code --allow-no-subscriptions --output none
if ($LASTEXITCODE -ne 0) { throw 'Sign-in failed.' }
az account show --query '{tenantId:tenantId, user:user.name, subscription:name, subscriptionId:id}' --output json
