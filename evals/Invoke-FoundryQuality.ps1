<#
.SYNOPSIS
    Foundry quality tooling for the advisor agent: rubric evaluator, built-in and rubric evaluations over saved
    turns or traces, Insights scans, and the agent optimizer for the hosted agent itself (instructions, skills and
    model selection) or for the brief-writer prompt agent. Evals\Invoke-QualityLoop.ps1 runs them as one loop.

.DESCRIPTION
    Runs evals/foundry_quality.py with the Foundry Python SDK (azure-ai-projects) as the signed-in identity of the
    isolated Azure CLI profile. The SDK is installed once into a virtual environment outside the repository
    (%LOCALAPPDATA%\advisor-harness\foundry-sdk-venv). Needs Foundry User on the Foundry account (judge model calls)
    and, for Insights on a hosted agent, Foundry Project Manager on the project.

.EXAMPLE
    .\evals\Invoke-FoundryQuality.ps1 rubric                    # generate the rubric evaluator
    .\evals\Invoke-FoundryQuality.ps1 dataset -Safety -Hours 6  # built-in + rubric (+ prompt-injection) on saved demo turns
    .\evals\Invoke-FoundryQuality.ps1 traces -Hours 24 -Safety  # built-in + rubric (+ prompt-injection) on recent traces
    .\evals\Invoke-FoundryQuality.ps1 evaluate -Safety          # the same judges on stored responses (prompt agents only;
                                                                # hosted-agent responses are session-scoped: 403)
    .\evals\Invoke-FoundryQuality.ps1 insights -Hours 48        # run an Insights scan and list findings
    .\evals\Invoke-FoundryQuality.ps1 optimize-hosted -Agent investment-advisor-agent-candidate   # optimize the hosted agent
    .\evals\Invoke-FoundryQuality.ps1 optimizer                 # the last job, its candidates and scores
    .\evals\Invoke-FoundryQuality.ps1 apply                     # write the best candidate into .agent_configs
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('rubric', 'evaluate', 'traces', 'dataset', 'insights', 'optimize', 'optimizer', 'optimize-hosted', 'apply', 'compare')][string]$Command,
    [double]$Hours = 24,
    [int]$Limit = 20,
    [string[]]$ResponseIds,
    # dataset: saved turn names (file stems in the work folder), e.g. rehearsal-prep-1; default: recent turns.
    [string[]]$Names,
    [switch]$Safety,
    [switch]$NoRubric,
    [switch]$WithTraces,
    [switch]$ListOnly,
    [double]$ScheduleHours = 0,
    # traces: the Foundry agent version whose traces to score (trace spans carry gen_ai.agent.id = name:version);
    # default: the latest version from Terraform.
    [string]$AgentVersion,
    # Hosted agent to scan, evaluate or optimize; default: the Terraform-managed agent.
    [string]$Agent,
    # optimize-hosted: test case IDs from hosted-optimizer-cases.json (default: all), candidates and parallel runs.
    [string[]]$Cases,
    [int]$Candidates = 3,
    [int]$Concurrency = 3,
    # optimize-hosted: extra model deployments to compare; default: Terraform's model_search_deployments.
    [string[]]$ModelSearch,
    [switch]$EstimateOnly,
    # optimizer, apply: the optimization job and candidate; default: the last job and its best candidate.
    [string]$JobId,
    [string]$Candidate,
    # apply: apply even if the guard finds test answers, an absolute date or a staff name in the candidate.
    [switch]$AllowLeaks,
    # dataset: a label for this evaluation; compare: the two labels to compare.
    [string]$Label,
    [string]$Before,
    [string]$After
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'scripts\Use-IsolatedAzure.ps1') -RequireLogin
$tf = Join-Path $repoRoot 'terraform'
$project = (terraform "-chdir=$tf" output -raw -no-color foundry_project_endpoint).Trim()
$model = (terraform "-chdir=$tf" output -raw -no-color chat_model_deployment).Trim()

$venv = Join-Path $env:LOCALAPPDATA 'advisor-harness\foundry-sdk-venv'
$python = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $python)) {
    Write-Output 'Installing the Foundry SDK into a local virtual environment (one time)...'
    python -m venv $venv
    & $python -m pip install --quiet --disable-pip-version-check -r (Join-Path $PSScriptRoot 'requirements-foundry.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the Foundry SDK.' }
}

if (-not $Agent) { $Agent = (terraform "-chdir=$tf" output -raw -no-color agent_name).Trim() }
$optimizerModel = (terraform "-chdir=$tf" output -raw -no-color optimizer_model_deployment).Trim()
$arguments = @($Command, '--endpoint', $project, '--model', $model, '--hours', $Hours, '--limit', $Limit, '--agent', $Agent)
if ($optimizerModel) { $arguments += @('--optimize-model', $optimizerModel) }
if ($Command -eq 'optimize-hosted') {
    # The optimizer judges with the optimizer deployment too, so its runs don't contend with the agent's model.
    if ($optimizerModel) { $arguments += @('--eval-model', $optimizerModel) }
    if (-not $ModelSearch) { $ModelSearch = @((terraform "-chdir=$tf" output -raw -no-color model_search_deployments 2>$null) -split ',' | Where-Object { $_ }) }
    if ($ModelSearch) { $arguments += @('--model-search') + $ModelSearch }
    if ($Cases) { $arguments += @('--cases') + $Cases }
    $arguments += @('--candidates', $Candidates, '--concurrency', $Concurrency)
}
if ($EstimateOnly) { $arguments += '--estimate-only' }
if ($JobId) { $arguments += @('--job-id', $JobId) }
if ($Candidate) { $arguments += @('--candidate', $Candidate) }
if ($AllowLeaks) { $arguments += '--allow-leaks' }
if ($Label) { $arguments += @('--label', $Label) }
if ($Before) { $arguments += @('--before', $Before) }
if ($After) { $arguments += @('--after', $After) }
if ($ResponseIds) { $arguments += @('--response-ids') + $ResponseIds }
if ($Names) { $arguments += @('--names') + $Names }
if ($Safety) { $arguments += '--safety' }
if ($NoRubric) { $arguments += '--no-rubric' }
if ($WithTraces) { $arguments += '--with-traces' }
if ($ListOnly) { $arguments += '--list-only' }
if ($ScheduleHours -gt 0) { $arguments += @('--schedule-hours', $ScheduleHours) }
if ($Command -eq 'insights') {
    # Insights judges with the optimizer's deployment: its scans rate-limited the chat model the agent uses.
    $judge = (terraform "-chdir=$tf" output -raw -no-color optimizer_model_deployment).Trim()
    if ($judge) { $arguments += @('--insights-model', $judge) }
}
if ($Command -eq 'traces') {
    if (-not $AgentVersion) { $AgentVersion = (terraform "-chdir=$tf" output -raw -no-color agent_version).Trim() }
    $arguments += @('--agent-version', $AgentVersion)
}
& $python (Join-Path $PSScriptRoot 'foundry_quality.py') @arguments
if ($LASTEXITCODE -ne 0) { throw "foundry_quality.py $Command failed." }
