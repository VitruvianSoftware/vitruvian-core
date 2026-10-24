---
name: receipts-report
description: Generate per-project engineering impact receipts, session transcript summaries, and token/error hotspot reports in HTML or CSV format. Use when the user asks for a session receipt, weekly/monthly agent usage report, or transcript hotspot analysis.
---

# Receipts Report Skill

Use this skill to generate structured impact receipts and analyze Antigravity
session transcripts across workspaces.

## Workflow

1. **Locate transcripts**: Antigravity stores session logs at
   `~/.gemini/antigravity/brain/<conversation-id>/.system_generated/logs/transcript.jsonl`.
2. **Parse & aggregate**: Use `sidecars/panel/lib/core.mjs` (`parseTranscriptJsonl`,
   `aggregateProjectReceipts`, `detectTokenHotspots`) or the sidecar's
   `/api/state` and `/api/export` endpoints to compute:
   - Total conversations, user prompts (`USER_INPUT`), and planner turns (`PLANNER_RESPONSE`)
   - Tool call breakdown (`tool_calls`), subagent invocations (`invoke_subagent`), and step errors
   - Truncated step fields (`truncated_fields`) and estimated token/character volume
   - Correlated git commits and pull requests per project
3. **Export**:
   - Use `renderHtmlReceipt(report)` to produce a self-contained HTML receipt.
   - Use `formatCsvReceipt(report)` to produce a spreadsheet-ready CSV table.
