<#
.SYNOPSIS
    Builds the agent image and releases it as a separate candidate hosted agent in the same Foundry project, so a
    change can be rehearsed, evaluated and optimized without touching the live agent.

.DESCRIPTION
    The candidate copies the live agent's definition (toolboxes, model, Work IQ mode, RAI policy, size) and changes
    only the image and ADVISOR_STORE_PREFIX, so its memory, preferences, history and checkpoints live in their own
    durable state stores. It uses the same toolboxes and Work IQ connection, but consent is stored per agent: each
    user consents once for the candidate as well (the first call returns the consent link). Promote a candidate by
    publishing the same image to the live agent with Publish-AgentImage.ps1.
    With Microsoft Purview on (ADVISOR_PURVIEW=on, copied from the live agent or set with -Environment), the
    candidate's own identity also gets Purview's three Microsoft Graph roles, which Terraform grants the live agent's.
    The candidate's name: -AgentName, else ADVISOR_CANDIDATE_AGENT from .env.local, else <live agent>-candidate.

.EXAMPLE
    .\scripts\Publish-CandidateAgent.ps1                                   # build and release the candidate
    .\scripts\Publish-CandidateAgent.ps1 -ImageUri <registry>/advisor-harness@sha256:...   # reuse an image
    .\scripts\Publish-CandidateAgent.ps1 -Model gpt-6-sol                   # try another model deployment
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,62}$')][string]$AgentName,
    [string]$Tag = ('candidate-' + (Get-Date -Format 'yyyyMMdd-HHmm')),
    [string]$ImageUri,
    [string]$FromAgent,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,30}$')][string]$StorePrefix,
    [string]$Model,
    [hashtable]$Environment = @{},
    # Shown in the Foundry portal; default: "Candidate of <live agent>".
    [string]$Description,
    [int]$TimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Use-IsolatedAzure.ps1" -RequireLogin
$repoRoot = Split-Path $PSScriptRoot -Parent
$tf = Join-Path $repoRoot 'terraform'
$project = (terraform "-chdir=$tf" output -raw -no-color foundry_project_endpoint).Trim()
if (-not $FromAgent) { $FromAgent = (terraform "-chdir=$tf" output -raw -no-color agent_name).Trim() }
if (-not $AgentName) { $AgentName = if ($env:ADVISOR_CANDIDATE_AGENT) { $env:ADVISOR_CANDIDATE_AGENT } else { "$FromAgent-candidate" } }
if ($FromAgent -eq $AgentName) { throw "The candidate needs its own name; $AgentName is the live agent." }
if (-not $StorePrefix) { $StorePrefix = $AgentName }

function Invoke-Foundry([string]$Method, [string]$Path, $Body) {
    $arguments = @('rest', '--method', $Method, '--url', "$project/$Path", '--resource', 'https://ai.azure.com', '-o', 'json')
    if ($null -ne $Body) {
        $file = New-TemporaryFile
        $Body | ConvertTo-Json -Depth 30 | Set-Content -Path $file -Encoding utf8
        $arguments += @('--body', "@$file", '--headers', 'Content-Type=application/json')
    }
    try { $raw = az @arguments 2>&1 } finally { if ($file) { Remove-Item $file -ErrorAction SilentlyContinue } }
    if ($LASTEXITCODE -ne 0) { throw "Foundry $Method $Path failed: $raw" }
    ($raw | Out-String) | ConvertFrom-Json
}

if (-not $ImageUri) {
    $registry = (terraform "-chdir=$tf" output -raw -no-color registry_name).Trim()
    $log = Join-Path $env:ADVISOR_WORK_DIR 'acr-candidate-build.log'
    Push-Location $repoRoot
    try { az acr build --registry $registry --image "${AgentName}:$Tag" --platform linux/amd64 --file Dockerfile . *> $log }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { Get-Content $log | Select-Object -Last 30; throw "Image build failed (full log: $log)." }
    $digest = (az acr repository show --name $registry --image "${AgentName}:$Tag" --query digest -o tsv).Trim()
    if ($digest -notmatch '^sha256:[0-9a-f]{64}$') { throw "Could not read the digest for ${AgentName}:$Tag." }
    $ImageUri = "$registry.azurecr.io/$AgentName@$digest"
    Write-Output "Built ${AgentName}:$Tag -> $ImageUri"
}

$source = (Invoke-Foundry get "agents/$([uri]::EscapeDataString($FromAgent))?api-version=v1").versions.latest
$definition = $source.definition
$definition.container_configuration.image = $ImageUri
$variables = [ordered]@{}
$definition.environment_variables.PSObject.Properties | ForEach-Object { $variables[$_.Name] = [string]$_.Value }
$variables['ADVISOR_STORE_PREFIX'] = $StorePrefix
if ($Model) { $variables['AZURE_AI_MODEL_DEPLOYMENT_NAME'] = $Model }
foreach ($key in $Environment.Keys) { $variables[$key] = [string]$Environment[$key] }
$definition.environment_variables = [pscustomobject]$variables

$body = [ordered]@{
    definition  = $definition
    description = if ($Description) { $Description } else { "Candidate of $FromAgent (image $Tag); separate state stores ($StorePrefix-*)." }
    metadata    = @{ candidate_of = $FromAgent; store_prefix = $StorePrefix }
}
$version = Invoke-Foundry post "agents/$([uri]::EscapeDataString($AgentName))/versions?api-version=v1" $body
Write-Output "Released $AgentName version $($version.version) from $FromAgent version $($source.version) ($($version.status))."

$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
    $current = Invoke-Foundry get "agents/$([uri]::EscapeDataString($AgentName))/versions/$($version.version)?api-version=v1"
    if ($current.status -match '^(active|succeeded|ready)$') { break }
    if ($current.status -match 'fail') { throw "$AgentName version $($version.version) failed: $($current | ConvertTo-Json -Depth 8 -Compress)" }
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)
Write-Output "$AgentName version $($current.version): $($current.status); identity $($current.instance_identity.client_id)"

# Microsoft Purview (ADVISOR_PURVIEW=on, copied from the live agent or set with -Environment): Terraform grants the
# live agent's identity Purview's three Microsoft Graph roles (terraform/agent.tf); this agent has its own identity, so
# it gets the same roles here. Without them Purview only logs errors and checks nothing.
function Grant-PurviewGraphRoles([string]$PrincipalId) {
    $graph = az ad sp show --id 00000003-0000-0000-c000-000000000000 --query '{id:id, roles:appRoles}' -o json | ConvertFrom-Json
    $granted = @(az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
            --query 'value[].appRoleId' -o json | ConvertFrom-Json)
    foreach ($name in 'ProtectionScopes.Compute.All', 'Content.Process.All', 'ContentActivity.Write') {
        $role = $graph.roles | Where-Object value -EQ $name | Select-Object -First 1
        if (-not $role) { throw "Microsoft Graph has no app role $name." }
        if ($granted -contains $role.id) { continue }
        $file = New-TemporaryFile
        @{ principalId = $PrincipalId; resourceId = $graph.id; appRoleId = $role.id } | ConvertTo-Json -Compress |
            Set-Content -Path $file -Encoding utf8
        try {
            az rest --method post --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($graph.id)/appRoleAssignedTo" `
                --body "@$file" --headers 'Content-Type=application/json' -o none
        } finally { Remove-Item $file -ErrorAction SilentlyContinue }
        if ($LASTEXITCODE -ne 0) { throw "Granting $name failed." }
        Write-Output "Granted $name to $AgentName's identity (Microsoft Purview)."
    }
}
if ($variables['ADVISOR_PURVIEW'] -eq 'on') {
    $principal = $current.instance_identity.principal_id
    if (-not $principal) {
        Write-Warning "No identity for $AgentName yet: rerun this script to grant it Microsoft Purview's Graph roles."
    } else {
        try { Grant-PurviewGraphRoles $principal }
        catch { Write-Warning "Could not grant $AgentName's identity Microsoft Purview's Graph roles ($($_.Exception.Message)): Purview checks nothing for it until they are granted. A Global Administrator can rerun this script." }
    }
}
