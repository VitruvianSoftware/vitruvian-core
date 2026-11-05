---
name: savvy-fleet
description: Inspect and manage the Savvy Fleet subagent telemetry panel and orchestrator flow state. Use when the user asks about running subagents, token/cost estimates, or wants to view the Savvy Fleet dashboard.
---

# Savvy Fleet (`savvy-fleet`)

`savvy-fleet` provides real-time visibility into Antigravity subagent executions (`invoke_subagent` and `send_message`), planned `savvy-flow` tasks, complexity tiers, and estimated token/cost telemetry.

## Opening the Panel

Surface a clickable sidecar link in your response whenever you launch a fleet of subagents or when the user asks to inspect subagent progress:

```markdown
[Savvy Fleet](sidecar://savvy-fleet/panel/)
```

## How Telemetry Works

1. **Transcript Inspection**: The sidecar inspects `~/.gemini/antigravity/brain/<conversation-id>/.system_generated/logs/transcript.jsonl` to count steps, tool calls, and `invoke_subagent` / `send_message` interactions.
2. **Hook Inbox**: `hooks/track-subagent.sh` captures `PostToolUse` events on `invoke_subagent` and `send_message` in `~/.gemini/antigravity/savvy-fleet-inbox/`.
3. **Flow & Step API**: The panel exposes `/api/state`, `/api/openui`, `/api/progress` (to set flow title, phase, and planned tasks), and `/api/step` (to update worker step progress).
