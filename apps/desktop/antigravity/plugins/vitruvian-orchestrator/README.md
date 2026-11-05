# vitruvian-orchestrator (Antigravity)

Antigravity desktop plugin for routing multi-domain engineering work across the Vitruvian specialist subagent roster.

## What is in this plugin today

- **`orchestrate` lead skill (`skills/orchestrate/SKILL.md`)**: Generated from `.agents/roster/` by `//tools/agent-roster`. Turns the active Antigravity session into the lead orchestrator that plans across five phases (`plan` → `design` → `delegate` → `review` → `close`), dispatches tasks to specialist subagents via `invoke_subagent` using the Antigravity model ladder (`pro` for `lead`, `flash` for `core` and `fast`), follows up via `send_message`, and reviews diffs adversarially.
- **Specialist subagents**: Live in the repository's `.agents/agents/*.md` (also generated from `.agents/roster/`), where Antigravity loads them for the workspace.

## What is coming next

- **Live orchestration sidecar panel (`sidecars/panel/`) and `PostToolUse` hook**: A side panel displaying the active flow header, task burn-down chart, task board with return rounds, live subagent progress/context telemetry from `invoke_subagent` / `send_message` hooks and `transcript.jsonl`, and estimated token spend per model, backed by the shared `packages/orchestrator-core` package.

## Install

Link directly from the `vitruvian-core` monorepo into Antigravity's plugin folder:

```bash
ln -s "$(pwd)/apps/desktop/antigravity/plugins/vitruvian-orchestrator" ~/.gemini/config/plugins/vitruvian-orchestrator
```

Or install via the Antigravity CLI from the repository:

```bash
agy plugin install https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/antigravity/plugins/vitruvian-orchestrator
```

Then enable `vitruvian-orchestrator` under Customizations → Installed in Antigravity.
