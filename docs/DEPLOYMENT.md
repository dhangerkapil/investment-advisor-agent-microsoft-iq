# Deploy the Investment Advisor Agent with Microsoft IQ to a new tenant

This guide takes a Microsoft 365 tenant and an Azure subscription to a working demo: the hosted agent, its chat UI,
the four Microsoft IQ sources (Work IQ, Fabric IQ, Foundry IQ and, with a key, Web IQ), the quality tooling and the
fictional Microsoft 365 story it researches. One script does the automated part; a handful of steps need a person and
are listed at the end of the run.

All names and data are fictional and for demo purposes only.

## What gets deployed

| Where | What |
|---|---|
| Azure resource group | Microsoft Foundry account and project; model deployments (`gpt-5.6-luna` for the agent, `gpt-5.5` for the optimizer and judges, `text-embedding-3-large` for Foundry IQ, optional model-search candidates); content-safety policy; Azure AI Search (Foundry IQ, Basic tier with the semantic ranker, optionally in another region); Azure Container Registry; Application Insights and Log Analytics; Azure Cosmos DB (chat history, private endpoint); Azure Container Apps (chat UI) with a virtual network; Fabric capacity (optional) |
| Foundry project | The hosted agent; connections for Work IQ (MCP and A2A), Fabric IQ, Foundry IQ (managed identity) and Web IQ (API key); toolboxes (Work IQ read tools and `list_agents`, Work IQ Chat over A2A, approval-gated drafts, governance probe, Fabric IQ, Foundry IQ, Web IQ); the rubric evaluator, the Insights monitor and the brief-writer prompt agent for the optimizer |
| Azure AI Search | The fictional firm library (six policy documents) in a hybrid text and vector index, a knowledge source and the `firm-knowledge` knowledge base (agentic retrieval). The documents are pushed into the index, so no storage account is needed |
| Microsoft Entra ID | App registrations for the toolbox OAuth client, the UI (API and browser), the Fabric IQ connection and the content publisher; the Work IQ service principal (shared by the tenant, adopted if it exists) |
| Microsoft Fabric | A workspace with the portfolio lakehouse (fictional clients, prices, positions, transactions) and the Portfolio Analyst data agent |
| Microsoft 365 | The story for the advisor (you): emails, a calendar event with Teams, Word documents in SharePoint, PDFs in OneDrive, and a Teams meeting to record, organized by the analyst |

## Before you start

**Tenant and people**

- A Microsoft 365 tenant with Exchange Online, SharePoint, OneDrive and Teams. A demo or developer tenant is best:
  the script writes fictional mail and files into the advisor's mailbox and the root SharePoint site.
- **The advisor:** you, signed in as a Global Administrator (app registrations, admin consent, the Work IQ service
  principal). The story's emails, meeting and files are addressed to you.
- **The analyst:** a second licensed user with a mailbox and Teams (`-AnalystUpn`). The analyst organizes the
  recorded meeting and is the second user in the permission demo.
- **Work IQ API access:** usage-based billing with Copilot Credits, and both users assigned to a spending policy that
  includes the Work IQ API (set up in the Microsoft 365 admin center; see the prerequisites in the
  [Work IQ overview](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/work-iq/)).

**Azure**

- A subscription where you are Owner (the script assigns roles) and that has Foundry hosted agents in the region.
- Model quota in the region (default `eastus2`): `gpt-5.6-luna` 150K TPM, `gpt-5.5` 100K TPM and
  `text-embedding-3-large` 50K TPM (Global Standard). More `gpt-5.5` capacity (300K or more) keeps Insights scans and
  the optimizer from being rate-limited.
- Azure AI Search capacity for a Basic service with the semantic ranker. If the region has none, the Platform step
  fails to create the service: rerun with `-SearchLocation` set to a region that has capacity (for example
  `centralus`); Search may sit in another region than the rest.
- Optional: a Fabric capacity (`-FabricSku F2` or larger; default `F8`). `-FabricSku ''` skips Fabric; the story
  then has no portfolio data agent, and the cross-check step uses the emails and documents only.
- Optional: a **Web IQ API key** (`-WebIqApiKey`, or the `WEBIQ_API_KEY` environment variable) for the public-web
  source; the key is sent only to Azure Resource Manager and stored in the Foundry connection. Without it the agent
  has no web tools. Web IQ is not an Azure online service: queries leave the Microsoft 365 and Azure compliance
  boundary, which is why the agent's boundary guard sends only public topics.

**Your machine (Windows)**

- PowerShell 7.4+, Azure CLI 2.70+, Python 3.12+ (3.14 recommended), Node.js 20+ (24 recommended), Git.
- No Docker: images build in Azure Container Registry. Terraform is installed into the deployment's private profile
  if it is missing.
- The scripts use a private Azure CLI profile per deployment (`%LOCALAPPDATA%\advisor-harness\<profile>`), so they
  never change your normal `az` sign-in. Use a different `-ProfileName` for each deployment on the same machine.

## Step 1: preview

```powershell
git clone https://github.com/dhangerkapil/investment-advisor-agent-microsoft-iq.git
cd investment-advisor-agent-microsoft-iq
$deploy = @{
    TenantId       = '<tenant guid>'
    SubscriptionId = '<subscription guid>'
    ResourceGroup  = 'rg-investment-advisor'
    AnalystUpn     = 'analyst@contoso.com'
}
.\scripts\Deploy-AdvisorDemo.ps1 @deploy -Step Config, Platform -WhatIf
```

The Config step writes two git-ignored files, `.env.local` and `terraform/terraform.tfvars`, signs the private
profile in by device code (sign in as the advisor), and prints the **story week**. It also writes
`web_boundary_terms`: the names of every fictional client, the advisor and the analyst, which the agent never sends
to Web IQ. `-WhatIf` then runs a Terraform plan without changing anything.

## Step 2: deploy

```powershell
.\scripts\Deploy-AdvisorDemo.ps1 @deploy -WebIqApiKey (Read-Host 'Web IQ API key (Enter to skip Web IQ)' -AsSecureString)
```

About 50 to 80 minutes. The steps run in order, and each one is safe to rerun alone with `-Step`:

| Step | What it does |
|---|---|
| Config | `.env.local` and `terraform.tfvars`; the advisor and analyst; the story week; the Web IQ boundary terms |
| Platform | Terraform: everything in the Azure table above |
| WorkIq | The Work IQ MCP connection and four toolboxes: read tools with `list_agents`, Work IQ Chat over A2A, governance probe, approval-gated drafts |
| Fabric | Workspace, lakehouse, data, the Portfolio Analyst data agent, its Foundry connection and toolbox |
| FoundryIq | Builds the six firm-library PDFs, embeds and pushes them into the Search index, creates the knowledge source, the `firm-knowledge` knowledge base, its project connection and toolbox |
| WebIq | With a key: the Web IQ connection and toolbox. Without one: skipped |
| Agent | Builds the agent image in the registry and releases a new agent version |
| Ui | Builds and deploys the chat UI |
| Quality | Rubric evaluator, Insights monitor with daily scans, one optimizer run on the brief-writer prompt agent |
| Content | The Microsoft 365 story: Friday files and emails, the OneDrive PDFs, the Teams meeting to record |
| Prewarm | Starts the agent and clears the demo switches |

Useful parameters:

| Parameter | Default | Notes |
|---|---|---|
| `-StoryMeetingDate` | the next Thursday | The client meeting that anchors the story week (a Thursday, `yyyy-MM-dd`) |
| `-AdvisorName` | your display name | The name the client and analyst use in emails |
| `-Location` | `eastus2` | Region for Foundry and the models |
| `-SearchLocation` | the region | Region for Azure AI Search (Foundry IQ) when the main region has no capacity |
| `-WebIqApiKey` | none | Adds Web IQ; to add it later, rerun `-Step Config, WebIq, Agent` with the key |
| `-ExistingFoundryAccountId` | none (create) | Use an existing Foundry account, for example from another resource group; see below |
| `-ExistingFabricCapacityId` | none (create) | Use an existing Fabric capacity, for example from another resource group; see below |
| `-ProfileName` | `demo` | Private profile folder and the suffix for tenant-wide names |
| `-AgentName` | `investment-advisor-agent` | The hosted agent's name |
| `-ChatModel`, `-ChatModelVersion`, `-ChatModelCapacity` | `gpt-5.6-luna`, `2026-07-09`, 150 | The agent's model deployment |
| `-FabricSku`, `-FabricLocation` | `F8`, the region | `''` skips Fabric |
| `-ExtraUserUpns` | none | More users who may use the UI |
| `-Force` | off | Rewrites `.env.local` and `terraform.tfvars` from the parameters |

### Use an existing Foundry account and Fabric capacity

By default the deployment creates everything, including the Foundry account with its model deployments and the
Fabric capacity. If your platform team already runs a Foundry account and a Fabric capacity, for example in a shared
resource group, point the deployment at them instead:

```powershell
.\scripts\Deploy-AdvisorDemo.ps1 @deploy `
    -ExistingFoundryAccountId '/subscriptions/<id>/resourceGroups/<shared-rg>/providers/Microsoft.CognitiveServices/accounts/<foundry>' `
    -ExistingFabricCapacityId '/subscriptions/<id>/resourceGroups/<shared-rg>/providers/Microsoft.Fabric/capacities/<capacity>'
```

- **Foundry:** the deployment creates only its own **project** in that account (plus a guardrail policy with the
  deployment's own name), so it never shares agents, toolboxes, connections, state stores or evaluations with other
  projects. It uses the account's model deployments, which must already exist: the chat model (`-ChatModel`,
  default `gpt-5.6-luna`), `gpt-5.5` (optimizer and judges) and `text-embedding-3-large` (Foundry IQ); the plan stops
  with the missing deployment's name otherwise. The account must allow project management (a Foundry resource of
  kind AIServices), and you need Owner or User Access Administrator on it for the role assignments. The project is in
  the account's region.
- **Fabric:** the deployment's own workspace, lakehouse and data agent go on that capacity. You must be a capacity
  administrator, and the capacity must be running during the Fabric step. Pausing it with
  `Set-FabricCapacityState.ps1` pauses it for everyone who uses it.
- **Everything else** (Azure AI Search, registry, Cosmos DB, Container Apps, Application Insights, Entra apps) is
  created in this deployment's resource group as usual.
- **Traces:** Foundry sends every project's traces to the Application Insights connected to the account, so the
  agent's traces, Insights and trace evaluations use the account's Application Insights. The deployment gives its
  project read access there (or, if the account has none, connects its own).
- **Removing** the deployment deletes its project, guardrail policy, role assignments and Fabric workspace from the
  shared resources and never deletes the account or the capacity.

## Step 3: the steps that need a person

The script prints these with the dates of your story week.

1. **Work IQ policy.** Microsoft 365 admin center > Agents > Tools > Registry (type MCP Server) > Work IQ MCP >
   Policies > Tenant Default: Directory lookups off; Allow write actions and Allow create on; partial update,
   replace and delete off. Changes can take a while to apply.
2. **Consent, once per user and agent.** Open the chat UI as the advisor, select **Authorize** on the consent banner
   (Work IQ), then **Retry**. Then ask *What are Michael Scott's top three holdings? Use the portfolio data.*: the
   first time, the banner shows a Fabric IQ **Authorize** link; open it, accept, and ask again. The first delegation
   to Work IQ Chat (*Delegate to Work IQ: ...*) shows one more banner, for the A2A connection. Foundry IQ (managed
   identity) and Web IQ (API key) need no user consent. Repeat as the analyst in a separate browser profile.
   Consent is stored per agent: a candidate agent (quality loop) asks once more.
3. **Record the review (about four minutes).** On the Friday of the story week, the analyst opens the Teams meeting
   the Content step created; you join, record, and read the script. The script with your dates is in the profile's
   work folder (`meeting-script.md`); the template is [hydration/meeting-script.md](../hydration/meeting-script.md).
4. **Monday.** Publish the IPS draft, then save the review as the agent's "last discussion":

   ```powershell
   .\hydration\Publish-DemoContent.ps1 -Stage Monday -ReplaceFiles 'IPS v2 DRAFT.docx'
   .\scripts\Invoke-AdvisorAgent.ps1 -Prompt "Save Friday's Q4 portfolio review with Michael Scott as our last discussion."
   ```

5. **Quality loop (optional, about an hour).** See [QUALITY-LOOP.md](QUALITY-LOOP.md).
6. **Demo day (Tuesday or Wednesday).** Minutes before the demo:

   ```powershell
   .\hydration\Publish-DemoContent.ps1 -Stage Live
   .\scripts\Start-DemoPrewarm.ps1
   ```

   Then follow [DEMO-SCRIPT.md](DEMO-SCRIPT.md).

## The story week

Everything in the story is dated relative to the client meeting on Thursday (`STORY_MEETING_DATE`). Weekday names,
"tomorrow" and trading days stay right; months, quarters and the year follow the date.

| Day | What exists | Created by |
|---|---|---|
| Thursday, a week before | Michael's agenda email for "tomorrow's review" | Content (Friday stage) |
| Friday | The quarterly review, recorded at 10:30 PM ET; meeting notes; IPS v1; the NVDA research note | You (recording); Content |
| Saturday | Michael's email: the house closing moved, $400,000 due before it | Content |
| Monday 4:45 PM ET | The analyst's alert: NVDA up 11.2%, Michael over his 25% limit | Content |
| Monday | The IPS v2 draft | Monday stage |
| Tuesday or Wednesday | **The demo.** Michael's 529-plan email arrives during it | Live stage |
| Thursday 10:00 AM ET | The client meeting the agent prepares for | Content (calendar) |

To preview another week without publishing anything:

```powershell
.\hydration\Publish-DemoContent.ps1 -Stage Friday, Meeting, OneDrive, Monday, Live -Preview -StoryMeetingDate 2027-03-04
```

To move a deployment to a new week, rerun with the new date and republish the data and content:

```powershell
.\scripts\Deploy-AdvisorDemo.ps1 @deploy -StoryMeetingDate <thursday> -Step Config, Fabric, Content
```

Messages and files from the old week stay in the mailbox and sites; delete them first for a clean story (see
[Remove everything](#remove-everything)).

Rehearsing on Monday, before the analyst's 4:45 PM alert? The agent treats anything dated after "now" as the future
and leaves it out, which is right but empties the story. Pin the agent's clock to the story's Tuesday morning in
`terraform/terraform.tfvars`, then rerun `-Step Platform`:

```hcl
agent_extra_environment = { ADVISOR_CLOCK_NOT_BEFORE = "2026-10-20T09:00:00-04:00" } # the story's Tuesday, 9:00 AM ET (-05:00 in winter)
```

Until that time the agent's clock reads the floor; after it, the real time applies again, so the floor never needs
removing.

## Verify

```powershell
.\scripts\Invoke-DemoRehearsal.ps1            # every demo prompt against the live agent, with a summary
.\scripts\Invoke-AdvisorAgent.ps1 -Prompt "Prepare me for Thursday's meeting with Michael Scott."
.\scripts\Invoke-AdvisorAgent.ps1 -Prompt "Michael wants to wire 400,000 dollars to his title company. What does our policy require?"
.\scripts\Invoke-AdvisorAgent.ps1 -Prompt "What is the public news on NVIDIA this week? Three bullets with links."
```

The rehearsal prints each turn's tool calls; a turn that needs consent prints a consent link instead (including the
Fabric IQ and Work IQ Chat links that arrive inside a tool result). The prep brief's Sources section is grouped by
IQ: Work IQ, Fabric IQ, Foundry IQ (document code and section) and Web IQ (publisher, date and link).

## Operate

- **Pause Fabric** when you are not demoing: `.\scripts\Set-FabricCapacityState.ps1 -State Paused` (and `Active`).
- **Release agent changes:** `.\scripts\Publish-AgentImage.ps1` builds and releases a new version of the live agent.
- **Try changes safely:** `.\scripts\Publish-CandidateAgent.ps1` releases a candidate next to the live agent, with
  its own state stores.
- **Rerun any step:** `.\scripts\Deploy-AdvisorDemo.ps1 @deploy -Step <name>`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| The agent answers with a consent link (`CONSENT_REQUIRED`) | Open the link as that user and accept. Links expire after about 10 minutes; ask again for a new one. |
| `TokenCreatedWithOutdatedPolicies` (Continuous Access Evaluation) or other sign-in errors after a Conditional Access change | Sign the private profile in again: `.\scripts\Connect-IsolatedAzure.ps1` (it clears the profile's cached tokens first), then rerun the failed step |
| The Content step can't create the Teams meeting | The organizer's calendar must allow `teamsForBusiness`; use an analyst whose mailbox can host Teams meetings |
| Insights or the optimizer fails with 429 | Raise the `gpt-5.5` capacity (`optimizer_model_capacity` in `terraform.tfvars`), then `-Step Platform` |
| Fabric steps fail or time out | Resume the capacity: `.\scripts\Set-FabricCapacityState.ps1 -State Active` |
| The Platform step can't create Azure AI Search ("insufficient capacity" or no semantic ranker) | Rerun with `-SearchLocation <region>` and `-Step Config, Platform` (`-Force` rewrites `terraform.tfvars`) |
| Connection `<name>` "already exist, and can only be updated by the workspace that created it" | Connection names are unique across a Foundry account. With `-ExistingFoundryAccountId` the scripts add this deployment's suffix automatically; if you created connections by hand, give them other names |
| The FoundryIq step can't upload documents or create the knowledge base | Wait a few minutes after Platform for the Search role assignments to apply, then rerun `-Step FoundryIq` |
| The agent says the firm library or the public web was not checked (`FIRM_KNOWLEDGE_UNAVAILABLE`, `WEB_UNAVAILABLE`) | Check the toolbox with `.\scripts\Test-ToolboxTool.ps1 -Toolbox advisor-foundryiq` (or `advisor-webiq`); for Web IQ, rotate the key with `.\scripts\Set-WebIqConnection.ps1 -Recreate` |
| A web question is answered with `WEB_QUERY_BLOCKED` | By design: the query named a client or staff member, or carried an email address, an amount or an account-like number. Ask about the public topic |
| New mail or files are not found yet | Work IQ indexes new mail within minutes and new SharePoint files can take longer; publish content a day ahead |
| Work IQ policy changes don't apply | They can take a while; the governance probe in the demo shows the policy that is in force |
| The Platform step stops with "the plan changes or destroys existing resources" | Review the plan, then rerun the step; it applies changes only after you allow them |
| The chat app shows "Foundry returned invalid activity arguments" | An older UI image: the preview hosting adapter (`agent-framework-foundry-hosting` 1.0.0b261015) sends each tool call's arguments twice (`{...}{...}`); the current UI keeps one copy. Redeploy the UI (`-Step Ui`, or `.\scripts\Publish-UiInstance.ps1 -AgentName <agent>` for an extra UI) |

## Remove everything

```powershell
.\scripts\Remove-AdvisorDemo.ps1 -WhatIf          # what would be removed
.\scripts\Remove-AdvisorDemo.ps1 -PurgeFoundry    # remove; asks before destroying
```

It deletes the Fabric workspace, candidate agents, extra UI instances, this deployment's script-created app
registrations, and everything Terraform created (including Azure AI Search with the Foundry IQ index and knowledge
base); the tenant's shared Work IQ service principal stays. The Microsoft 365 story stays too; delete it by hand if
you keep using the tenant:

- The advisor's mailbox: the emails from Michael Scott and the analyst's NVDA alert, and the "Year-end planning -
  Michael Scott" event.
- The analyst's calendar: the recorded review meeting.
- The root SharePoint site: the `Client Files/Michael Scott` and `Research` folders.
- The advisor's OneDrive: `Client Files/Michael Scott`.
