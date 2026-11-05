# receipts-report: session impact receipts and transcript analytics

The `receipts-report` plugin indexes Antigravity conversation transcripts under
`~/.gemini/antigravity/brain/<conversation-id>/.system_generated/logs/transcript.jsonl`
and aggregates per-project activity, tool usage, subagent fan-out, context
truncations, and shipped commits/PRs.

When the user asks for an engineering receipt, session summary, or token/tool
hotspot report:
1. Read or query the Receipts Report sidecar panel state (or follow the
   `receipts-report` skill) to inspect aggregated metrics across the requested
   time window (`7d`, `14d`, `30d`, or `all`).
2. Highlight shipped outcomes (commits, PRs opened/merged) alongside session
   cost signals (planner turns, tool calls, subagents invoked, and truncated
   step fields).
3. Offer to export a standalone HTML report or CSV receipt when the user wants
   an artifact they can share or archive.
