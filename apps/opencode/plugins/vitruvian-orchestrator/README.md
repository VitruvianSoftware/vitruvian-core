# Vitruvian Orchestrator — OpenCode Live Panel

OpenCode server + TUI plugin for the `orchestrate` skill (`packages/orchestrator-core`). It registers the `progress` and `step` tools, tracks subagent sessions (`parentID`) and lead/worker token usage per root session, and renders a live orchestrator sidebar in the OpenCode TUI.

## What It Shows

1. **Header**: Flow title, 5-phase lifecycle pills (`plan`, `design`, `delegate`, `review`, `close` — completed phases marked `✓`, current phase highlighted), `accepted N of M`, and total estimated cost (`est. $X.XX`).
2. **Burn-down**: Compact Unicode text sparkline (`▁▂▃▄▅▆▇█`) of remaining task counts over time against the linear ideal line (`total → 0`), plus replan markers (`⟳`).
3. **Task Board**: One row per task (`#id`, `title`, `[specialist/tier]`, derived `state`, return round `rN` when `round > 0`, and `waits on #x` when blocked by upstream dependencies).
4. **Agents**: One row per lead/worker run (`agent`, `model`, `effort`, `steps` `done/total` or `ctx %`, token count, `est. $cost` or `unpriced`, elapsed duration, and `status`).
5. **Spend**: Breakdown of `lead` vs `workers` USD spend, per-model spend, and unpriced model token counts.

When no plan has been reported for the active root session, the sidebar shows:
`Orchestrator panel fills in when the lead skill reports a plan.`

## Tools Registered

- `progress({ title?, phase?, tasks?, accept?, return?, finished? })` — called by the lead orchestrator to publish or replan tasks, advance phases, accept/return reviewed tasks, and close the flow.
- `step({ done, total, note? })` — called by worker subagents to report sub-step progress (`0 <= done <= total`, `total >= 1`).

## Discovery & State Sharing

- **Project-level discovery (zero install inside this repo)**: OpenCode scans `.opencode/plugins/` when started from the repository root. `.opencode/plugins/vitruvian-orchestrator/{server.ts,tui.tsx}` re-export `apps/opencode/plugins/vitruvian-orchestrator/{server.mjs,tui.tsx}`.
  > Note: OpenCode 2.2.5's `ConfigPluginSource.scan` verifies that `Bun.resolveSync` stays inside the scanned plugin directory, so `.opencode/plugins/vitruvian-orchestrator/` uses real loader files rather than a directory symlink.
- **Optional user-level install (for sessions outside this repo)**: Run `./apps/opencode/plugins/vitruvian-orchestrator/install.sh` to install the loader files into `~/.config/opencode/plugins/vitruvian-orchestrator/`.
- **State sharing**: The server plugin writes per-root-session flow state atomically to `~/.local/state/opencode/vitruvian-orchestrator/state.json` (and `<rootSessionID>.json`), which the TUI sidebar component reads.

## Testing

```sh
bazel test //apps/opencode/plugins/vitruvian-orchestrator/...
```
