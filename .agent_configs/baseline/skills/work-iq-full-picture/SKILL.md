---
name: work-iq-full-picture
description: Show the full power of Work IQ for one client in one answer - exact Graph reads of mail and calendar, search by meaning across the recorded meeting, Teams chats, OneDrive and SharePoint, Copilot reasoning that compares two exact files and reads a chart image, and a whole task delegated to Work IQ's own agent over A2A - all read as the advisor, with every item cited.
---

Use this skill when the advisor asks for everything Work IQ or Microsoft 365 knows about a client, or asks to see
what Work IQ can do (for example a question that starts with "Work IQ:"). Use Work IQ only: no Fabric IQ, Foundry IQ
or Web IQ.

1. In ONE step, make all of these calls in parallel (one turn, never one after another):
   - `workiq___fetch` with two paths, direct Microsoft Graph reads (complete and current):
     `/me/calendarView?startDateTime=<UTC now minus 10 days>&endDateTime=<UTC now plus 21 days>&$select=id,subject,
     start,end,isOnlineMeeting,organizer,webLink&$orderby=start/dateTime&$top=50` and
     `/me/messages?$search="<client>"&$top=10&$select=id,subject,from,receivedDateTime,body,webLink`.
   - `workiq___retrieve`, capabilities `[{"name": "Meetings"}]`: "<client> what was said and decided in the recent
     review meeting, with the client's own words".
   - `workiq___retrieve`, capabilities `[{"name": "TeamsMessages"}]`: "<client> portfolio, limits and trims in Teams
     chats with colleagues".
   - `workiq___retrieve`, capabilities `[{"name": "OneDriveAndSharePoint"}]`: "<client> signed investment policy
     statement, IPS draft, meeting notes and portfolio overview".
   - `delegate_to_work_iq` (Work IQ Chat over A2A): "What has <client> asked the advisor for in recent emails and
     meetings, and what is still open? Cite each item."
2. In ONE step, with the file URLs exactly as retrieve returned them (skip a call whose files were not found, and
   say so):
   - `workiq___ask` with `fileUrls` set to the signed IPS and the IPS draft: "Compare these two investment policy
     statements term by term: list each term that changed with the v1 value, the v2 value, and whether v2 is
     signed."
   - `workiq___ask` with `fileUrls` set to the portfolio overview: "Read the chart of the largest position's weight
     against its limit: the high and the low since the first of last month, and where it ended, each with its date.
     Say which values are printed on the chart and which are estimated from the image."
3. Answer with one short section per Work IQ capability, each item dated and cited:
   - **Exact reads (`fetch`, Microsoft Graph through Work IQ):** the next meeting and the latest emails.
   - **Search by meaning (`retrieve`):** the recorded meeting (quote the client's own words exactly when the result
     has them, else the meeting notes), the Teams chat, and the files, listed as "OneDrive: <file>, <file>;
     SharePoint: <file>".
   - **Copilot reasoning over exact files (`ask` with `fileUrls`):** what changed between the signed IPS and the
     draft, and which version is in force (an unsigned draft never overrides a signed IPS).
   - **A chart read from an image (`ask`):** the values, each marked printed or estimated. Don't cite a page
     number unless you verify it with `inspect_document`.
   - **A whole task, delegated (A2A, Work IQ's own agent):** what is still open, with the A2A task ID (first 8
     characters).
   - One closing line, exactly: "One answer, every kind of Work IQ call: fetch, retrieve, ask and A2A, across mail,
     calendar, the meeting recording, Teams, OneDrive and SharePoint, all as you, under one delegated permission and
     the tenant's Work IQ policy."
   Keep it under 450 words, and end with the `workiq_references` block for every cited email, event, Teams message
   and file.
