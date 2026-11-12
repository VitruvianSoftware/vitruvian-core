# vitruvian-orchestrator (Antigravity)

Antigravity desktop plugin that coordinates specialist helpers across a planned engineering flow and shows live progress, spend, and team messages in a sidecar panel.

## What is in this plugin

- **`orchestrate` lead skill (`skills/orchestrate/SKILL.md`)**: Turns the active Antigravity session into the lead that plans across five phases (`plan` → `design` → `delegate` → `review` → `close`), dispatches specialist helpers (`wren`, `scout`, `compass`, `quill`, and peers), reviews their work, and closes the flow. See [How the agent team works](../../../../docs/concepts/agent-team.md).
- **Live Orchestrator panel (`sidecars/panel/`)**: Shows five **Flow** cards — **Header**, **Burn-down**, **Task Board**, **Agents**, and **Spend**. Flows with no board posts and no pause, retire, or kill events stay on this single **Flow** view. Once the flow has a post or a pause, retire, or kill event, a tab bar adds **Board**, **Members**, and **Graph**.
- **Orchestration rule (`rules/AGENTS.md`)**: Reminds the lead and helpers to report progress and surfaces the `[Orchestrator](sidecar://vitruvian-orchestrator/panel/)` pill in chat.

## Shared board, tools, waking, and member states

- **What the board is**: The board is a shared message list for the helpers and the lead, shown as numbered posts (`#1`, `#2`, and so on). Recipients appear as `@name` (`@all` displays as `everyone`), and replies show `↩ #<n>`.
- **What helpers post**: Helpers post results, questions, and defect lists (plus short status notes) so teammates and the lead can read findings in one place.
- **Tools**:
  - `post`: Adds a message to the board with optional recipients, kind (`result`, `question`, `defect`, or `note`), and `replyTo` post number.
  - `board`: Reads numbered posts from the board, with optional filters for recipient, author, kind, or search words. For a helper, calling `board` with no recipient (or `to: "me"`) returns posts addressed to that helper or to everyone.
  - `step`: Called by a helper to report step progress (`done`, `total`, `note`) or a pause reason (`paused: "quota"` or `paused: "error"`, plus an optional `detail` such as `429 Resource Exhausted`).
  - `progress`: Called only by the lead to publish or update the task plan, change phases, accept or return tasks, close the flow, or `retire` / `kill` a helper.
- **How waking works**: When a post mentions a waiting helper (`@name`), Antigravity delivers a wake straight to the helper's own conversation once for that mention (`@lead` wakes the lead conversation). Only the lead's `@all` wakes everyone who is waiting; `@all` from a helper never broadcasts wakes. Every forwarded post is clearly marked and shown to other agents as helper content, never as instructions from the user, the lead, or the system.
- **Member states**:
  - `working`: The helper is actively running its turn or a background task.
  - `waiting`: The helper finished its turn and is standing by so an `@mention` on the board can wake it.
  - `paused`: The helper reported a pause reason (`quota` or `error`). While the flow is open, its row shows an amber `paused: <reason>` badge in place of `running`, and the **Members** tab shows its pause detail whether or not it has posted.
  - `retired`: The helper is done for good — either retired early by the lead with `progress` (`retire`) or finished when the flow closes. Retired helpers are grouped under **Retired** in the **Members** tab and never change the status badge on **Flow** agent rows.
  - `killed`: The lead marked the helper as killed with `progress` (`kill`). It shows a red `killed` badge and is no longer woken by board posts. This does not stop a helper that is still running; the lead stops it in the tool itself.

## Who talks to whom

The **Graph** tab shows helpers as points on a circle, with a line for each pair that mention each other. The more two helpers mention each other, the thicker their line, and the line shows the count. Replay controls let you review interactions over time with play/pause, step, a slider, and `Live`. `Hide inactive` hides killed or retired helpers.

## Choosing a Gemini model per task

The lead can set a model on a task and put `Gemini model: <id>` in the brief; the helper uses it instead of its default. Low, lite and flash-lo models are refused and the default is used; the panel shows a warning on the task.

## A worktree per helper

The lead can give a task its own worktree and put `Worktree: <branch>` in the brief; the helper creates it with the repo's worktree tool (or reuses it), works there, reports the path, and the panel shows it on the helper. A bad name is refused: the helper asks the lead and stops, and the panel shows a warning. Give parallel helpers on the same repository separate worktrees.

## Safety

The model and worktree are only ever read from the lead's brief, never from board posts, and are checked before use.

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

Adapted from [`savvy-fleet`](../savvy-fleet/README.md) (MIT, VitruvianSoftware) for the Antigravity sidecar layout and powered by [`packages/orchestrator-core`](../../../../packages/orchestrator-core/README.md).

## Subdirectories & Boundaries
- [mcp](./mcp/README.md): MCP server exposing `progress`, `step`, `post`, and `board`.
- [sidecars](./sidecars/README.md): Sidecar UI and background wake watcher for the Orchestrator panel.
