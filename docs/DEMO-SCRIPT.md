# Demo script: the Investment Advisor Agent with Microsoft IQ

A 50-minute demo in nine parts, with every prompt to paste and what to point at. All names and data are fictional
and for demo purposes only.

## The story in one minute

You are an investment advisor. Your client **Michael Scott** meets you on **Thursday**. Since your quarterly review
last **Friday**:

- his NVDA position went over the 25% single-stock limit in his investment policy statement (IPS);
- his house closing moved up, and he needs $400,000 wired before it;
- his tax budget is in dispute: $20,000 in the signed IPS, $15,000 from his accountant;
- and minutes before the demo he asks about a 529 college plan.

The facts are scattered: the portfolio system (Fabric IQ), PDFs in OneDrive, the IPS and its draft in SharePoint,
email, the recorded Teams review and the analyst's alert (Work IQ), the firm's policies (Foundry IQ) and the news
(Web IQ). The agent pulls them together **as you**, and the app shows every call it makes. The dates follow your
deployment's story week ([DEPLOYMENT.md](DEPLOYMENT.md#the-story-week)); run the demo on the Tuesday or Wednesday
before the Thursday meeting.

## Before you start

| When | Do |
|---|---|
| 1 hour before | **Window A** (Edge InPrivate): sign in as the advisor (the admin who deployed). **Window B** (another browser profile): the chat UI as the analyst. Zoom 125%, notifications off. |
| 45 minutes before | In window A, open: the chat UI (`terraform -chdir=terraform output -raw ui_url`); the Microsoft 365 admin center (Agents > Tools > Registry > Work IQ MCP > Policies); the Foundry portal on your agent (Traces, Insights), on Evaluations, and on the optimizer; Outlook Drafts. |
| 15 minutes before | `.\scripts\Start-DemoPrewarm.ps1 -IncludeFabric` (resumes Fabric, warms the agent, resets the demo switches). |
| 10 minutes before | In the app: **New session**, send prompt 1.1, keep it as a backup. Delete older sessions and any Outlook drafts. |
| 2 minutes before | `.\hydration\Publish-DemoContent.ps1 -Stage Live` (Michael's 529 email arrives "now"). |

## How to drive the app

- **New session** (top left) starts a fresh conversation. Wait for each answer before sending the next prompt.
- Under each answer: **source chips** open the cited item on the right (**Open original** opens the real item), and
  the **X-ray** bar lists every call the agent made, each with its input and output.

| X-ray entry | What to say |
|---|---|
| `load_skill` | It picked a playbook for this task. |
| `recall_client_memory` | Memory from the last meeting, from the Foundry state store. |
| `workiq / fetch` | An exact Microsoft Graph read through Work IQ: the calendar, the inbox. |
| `workiq / retrieve` | A search by meaning across files, meetings or Teams, with citations. |
| `workiq / ask` | Microsoft 365 Copilot's reasoning over the user's data; it can read a chart image in a file, reason over exact files (`fileUrls`) or ask another Copilot agent (`agentId`). |
| `workiq / list_agents` | The Copilot agents this user can reach through Work IQ. |
| `delegate_to_work_iq` | Work IQ Chat over A2A: Work IQ's own agent answered the whole question and returned an A2A task. |
| `query_portfolio_data` | Fabric IQ: the portfolio data agent, the system of record. |
| `search_firm_knowledge` | Foundry IQ: the firm's knowledge base in Azure AI Search, as the project's managed identity. |
| `search_public_web`, `read_public_web_page` | Web IQ: public news and pages, outside the Microsoft 365 boundary; a guard blocks client data before it leaves. |
| `inspect_document` | A harness tool: it downloads the PDF through Work IQ, as the user, and verifies the page. |
| `rebalancing_check`, `liquidity_check`, `to_eastern_time` | The math and the time zones run in code, not in the model. |

## 1. Meeting prep across the four IQs (8 minutes)

**1.1** New session:

```text
Prepare me for Thursday's meeting with Michael Scott.
```

Point at: the meeting time from the calendar; NVDA above the 25% limit, with Fabric IQ and the analyst's email
agreeing; the earlier closing and the $400,000; the two tax budgets side by side; the firm rules each risk triggers
(Foundry IQ, by document and section); one line of public context (Web IQ, with its link); questions to ask; and
**Sources grouped by IQ**. Open the X-ray: all four IQs in one parallel step.

**1.2** Same session:

```text
In Friday's Q4 portfolio review, what exactly did Michael say about his tax budget and his house? Quote the meeting transcript, and list the action items with their owners and whether each has been done since.
```

Point at: verbatim quotes from the Teams transcript, the action items, and which are done (the IPS v2 draft exists).

## 2. One position, five places (8 minutes)

**2.1** Same session:

```text
Find the chart of Michael Scott's NVDA weight against its limit. What were the high and the low since September 1, how close did it come to the limit, and where did it end?
```

Point at: the PDF and its page in OneDrive (verified), values read from the chart image by Work IQ `ask`, and the
"around" wording, because chart readings are approximate.

**2.2** Same session:

```text
Since that chart, where does Michael's NVDA position stand now? Check the analyst's latest email against the portfolio data in Fabric, tell me whether they agree, what Michael and the team said about trimming it, and what a trim to the limit would mean.
```

Point at: the analyst's email and Fabric agree (or the difference is flagged), the trim math from
`rebalancing_check`, and the tax consequence. No recommendation: the agent reports facts.

## 3. Work IQ versus calling Graph (6 minutes)

**3.1** New session:

```text
How is Work IQ different from just calling the Graph API? Show me side by side on this question: where is the chart of Michael Scott's NVDA position against its limit, and what did Michael ask about it by email?
```

**Say:** "Graph is the API to Microsoft 365's data: you ask for a path and get exactly that, and search by meaning,
reading the content, permissions and policy are your code. Work IQ sits on top of Graph and gives the agent
understanding: search by meaning across mail, files, meetings and chats, with citations, and Copilot's reasoning,
which can read a transcript or a chart. All of it runs as the signed-in user, behind one permission and one tenant
policy. And you don't lose Graph: Work IQ's `fetch` is Graph, through the same governed door."

| | Microsoft Graph | Work IQ |
|---|---|---|
| You send | A path, such as `/me/messages?$search=...` | A question, or a Graph path (`fetch`) |
| You get back | Records that match the path or keywords | Passages from inside the content with citations, or Copilot's answer (`ask`) |
| Search by meaning | You build it: download, chunk, embed, index, keep in sync | Built in, across mail, files, meetings, Teams and people |
| Permissions | A scope per workload; app-only is possible | One delegated permission: always the user's own access |
| Policy | App consent and Conditional Access | Also a tenant Work IQ policy checked on every call |

Graph is still the right tool for background jobs with no signed-in user, bulk export or sync, and the fastest exact
lookups.

## 4. The firm's rules and the public web: Foundry IQ and Web IQ (6 minutes)

**4.1** New session:

```text
Michael wants to wire $400,000 to his title company for the closing. What does our firm policy require before we send it?
```

Point at: the answer cites **OPS-220** by section (signed authorization, callback verification on a number already
on file, dual approval, independent confirmation of the title company's instructions, lead time). Foundry IQ is the
firm's own library in an Azure AI Search knowledge base, read as the project's managed identity: inside Azure, no
user consent.

**4.2** Same session:

```text
What is the public news on NVIDIA this week? Three bullets with links.
```

Point at: each item's publisher, date and link. The X-ray may show one query **blocked at the boundary** because it
carried an amount, then a rephrased query: the guard is conservative by design.

**4.3** Same session:

```text
Search the web for Michael Scott's NVDA position and his stake.
```

The agent refuses: Web IQ is outside the Microsoft 365 and Azure boundary. **Say:** "Two layers: the instructions
say never send client data to the web, and if a model ever tried, the boundary guard in code blocks client and staff
names, email addresses, amounts and account numbers before anything leaves. Public prices never reprice a client's
position; the portfolio system is the system of record."

## 5. Work IQ three ways: MCP, A2A and Copilot agents (7 minutes)

**5.1** New session:

```text
Compare Michael Scott's signed IPS with the IPS v2 draft. Which terms changed, and which version is in force?
```

Point at: a term-by-term table (tax budget $20,000 to $15,000, the new ESG tilt, the effective date "upon client
signature") and "v1 stays in force until Michael signs v2". Work IQ `ask` with `fileUrls`: Copilot reasoned over
exactly those two files.

**5.2** Same session:

```text
Delegate to Work IQ: what did Michael Scott ask me for in his recent emails, and what is still open?
```

Point at: `delegate_to_work_iq` in the X-ray: an **A2A** task, answered end to end by Work IQ's own agent, with
links. **Say:** "MCP gives our agent Work IQ's tools to compose; A2A hands a whole task to Work IQ as a peer agent;
REST is for an app calling Work IQ directly. Same identity, same policy."

**5.3** Same session:

```text
Which Copilot agents can you work with through Work IQ?
```

Point at: the Microsoft agents and the organization's own agents this user can reach (`list_agents`), each of which
the agent can ask with its `agentId`.

## 6. Governance (8 minutes)

**6.1** In the admin center tab, show the Work IQ **Tenant Default** policy: directory lookups off; write and create
on; update, replace and delete off.

**6.2** New session:

```text
What is this agent allowed to do with Work IQ? Test it.
```

A live test: reading your own mail and files is allowed; directory lookups, updates and deletes are denied by the
tenant policy (the update and delete target an item that does not exist, so nothing changes).

**6.3** Same session:

```text
Draft a short follow-up email to Michael Scott confirming our Thursday meeting and listing the three agenda topics from his latest email.
```

The agent stops and asks for approval. Approve it, then show the draft in Outlook Drafts: created, not sent.

**6.4** In window B (the analyst), new session, send prompt 1.1. The analyst's brief has the shared files and the
meeting, but not Michael's emails to you or your saved memory. Nobody wrote a permission check: Work IQ runs as the
signed-in user, and the agent's memory is separate for each user.

## 7. Durability: a process stops between writes (8 minutes)

**7.1** New session: `Arm the process crash test.`

**7.2** Same session: `Run a durable meeting pack for Michael Scott.` The pack runs in waves (Work IQ documents and
meetings; calendar and email; then Fabric IQ, Foundry IQ and Web IQ). After wave 2 writes its checkpoints and
**before** the progress marker moves, the agent's process really stops; the app says **process stopped**.

**7.3** New session (the crashed one stays locked, on purpose, so a half-finished turn is never replayed):

```text
What is stored durably for Michael Scott right now?
```

The run is open; the progress marker still points at wave 2; checkpoints 1 to 4 exist; attempt 1 has no end record,
so it was interrupted; and a different process is answering.

**7.4** Same session: `Resume the durable meeting pack for Michael Scott.` Attempt 2 restores wave 1's checkpoints
(the marker had passed them), verifies and **reuses wave 2's two checkpoints written just before the stop** (no work
repeated, no duplicate write), moves the marker with its ETag, and runs only wave 3 (Fabric IQ, Foundry IQ, Web IQ).
The durability report is a timeline: each attempt, process, event and store write.

**Say:** "This is Foundry's guidance for long-running agents: write the checkpoint first, then move the marker with
an ETag, and reconcile after a crash. The state store kept the work; the harness decided what was done and where to
resume."

## 8. What changed since the last discussion (3 minutes)

**8.1** New session:

```text
What changed since my last discussion with Michael Scott?
```

Point at: the comparison starts from the review saved in memory, and lists only what changed since, each with its
source and date, including the 529 email that just arrived.

## 9. The quality loop (4 minutes)

In the Foundry portal:

- **Traces:** the trace of the brief from 1.1: every Work IQ call, the harness steps, each model call with time and
  tokens.
- **Evaluations:** today's turns scored by built-in judges (task adherence, groundedness, tool use, prompt
  injection) and the rubric evaluator generated from the agent's instructions.
- **Insights:** recurring problems found in real traces, each with evidence and a suggested fix.
- **Agent optimizer:** candidates for the instructions, skills and model, scored against the baseline; a person
  promotes the winner after it wins on a candidate agent ([QUALITY-LOOP.md](QUALITY-LOOP.md)).

**Say:** "That's the loop: observe, evaluate, optimize, and release only what measurably wins."

## If something goes wrong

| What happens | Do |
|---|---|
| An answer is slow | Open the X-ray and talk through the calls as they finish. |
| A consent link appears | Open it in the same window, accept, then **Retry**. |
| Fabric is not answering | `.\scripts\Set-FabricCapacityState.ps1 -State Active`, wait two minutes, retry. |
| The 529 email is missing | Rerun `.\hydration\Publish-DemoContent.ps1 -Stage Live -ReplaceMail 'One more thing before Thursday: 529 plan'`. |

## After the demo

Delete the draft in Outlook Drafts, pause Fabric (`.\scripts\Set-FabricCapacityState.ps1 -State Paused`), and for a
fresh week rerun the deployment with a new `-StoryMeetingDate`.
