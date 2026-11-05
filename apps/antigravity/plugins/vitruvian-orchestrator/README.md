# vitruvian-orchestrator (Antigravity)

Antigravity desktop plugin for routing multi-domain engineering work across the Vitruvian specialist subagent roster with a live orchestration telemetry panel.

## What is in this plugin

- **`orchestrate` lead skill (`skills/orchestrate/SKILL.md`)**: Generated from `.agents/roster/` by `//tools/agent-roster`. Turns the active Antigravity session into the lead orchestrator that plans across five phases (`plan` → `design` → `delegate` → `review` → `close`), dispatches tasks to specialist subagents via `invoke_subagent` using the Antigravity model ladder (`pro` for `lead`, `flash` for `core` and `fast`), follows up via `send_message`, and reviews diffs adversarially.
- **MCP telemetry server (`mcp/server.mjs`, `mcp_config.json`)**: Minimal dependency-free stdio MCP server exposing two tools:
  - `progress` (called by the lead): records the task plan (`title`, `tasks`), phase transitions (`plan`, `design`, `delegate`, `review`, `close`), review outcomes (`accept`, `return`), and flow completion (`finished`) to `~/.gemini/antigravity/vitruvian-orchestrator/flows/<root_conversation_id>.jsonl`.
  - `step` (called by a worker subagent): records `{ done, total, note }` step progress against the calling worker's run ID (resolved via `_meta["antigravity.google/conversation_id"]` and routed to `_meta["antigravity.google/root_conversation_id"]`).
- **Live Orchestrator sidecar panel (`sidecars/panel/`)**: Folds flow JSONL events and `transcript.jsonl` `invoke_subagent` / `send_message` runs through `orchestrator-core.mjs` (`packages/orchestrator-core`) and renders five live sections:
  1. **Header**: flow title, phase pills (`plan`, `design`, `delegate`, `review`, `close`), accepted task counter (`accepted N of M`), and estimated cost (`est.`).
  2. **Burn-down**: inline SVG chart of remaining tasks over time with a dashed ideal line and vertical markers at each re-plan.
  3. **Task board**: numbered tasks with title, specialist, tier, status colour (`accepted` green, `running` blue, `review`/`waiting` amber, `returned`/`error` red), return round, and `"waits on #x"` dependency badges.
  4. **Agents**: active and finished runs with specialist mascot, model, effort, `done/total` step progress or context percentage, token count, estimated cost or `"unpriced"`, elapsed duration, and run status.
  5. **Spend**: lead vs. worker cost split, per-model cost breakdown, and unpriced run token totals.
- **Orchestration rule (`rules/AGENTS.md`)**: Instructs the lead session to call `progress` on plan creation, phase transitions, task accept/return, and close; instructs workers to call `step`; and surfaces the sidecar pill.

## Opening the panel

Click the sidecar pill surfaced in chat:

`[Orchestrator](sidecar://vitruvian-orchestrator/panel/)`

Or open **Orchestrator** from the Antigravity auxiliary side pane. For standalone local testing:

```bash
PORT=47811 VITRUVIAN_ORCH_DIR="$(pwd)/apps/antigravity/plugins/vitruvian-orchestrator/sidecars/panel/testdata" \
  node apps/antigravity/plugins/vitruvian-orchestrator/sidecars/panel/main.mjs
```

## Install

Install via the Antigravity CLI from the repository:

```bash
agy plugin install apps/antigravity/plugins/vitruvian-orchestrator
```

Or link directly from the `vitruvian-core` monorepo into Antigravity's plugin folder:

```bash
ln -s "$(pwd)/apps/antigravity/plugins/vitruvian-orchestrator" ~/.gemini/config/plugins/vitruvian-orchestrator
```

## Credits

Adapted from [`savvy-fleet`](../savvy-fleet/README.md) (MIT, VitruvianSoftware) for Antigravity sidecar architecture and `transcript.jsonl` subagent run extraction, and powered by the shared [`packages/orchestrator-core`](../../../../packages/orchestrator-core/README.md) state machine.
