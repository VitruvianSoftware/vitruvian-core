# Orchestrator Sidecar Panel (Antigravity)

The **Orchestrator** sidecar panel shows live task progress, helper status, spend, and team messages for the current Antigravity flow.

## Views and tabs

- **Flow**: Always available. Shows the flow header and phase strip, burn-down chart, numbered task board, agent run rows (`running`, `done`, `error`, plus amber `paused: <reason>` in place of `running` or red `killed`), and estimated spend.
- **Tab bar (`Flow` · `Board` · `Members` · `Graph`)**: Hidden on plain flows. It appears as soon as the flow has at least one board post or any pause, retire, or kill event.
- **Board**: A shared message list for the helpers and the lead, shown as numbered posts (`#1`, `#2`, and so on) with search, author/recipient/kind filters, expandable long posts, and a `Follow` / `Jump to latest` toggle. Recipients show as `@name`, `@all` shows as `everyone`, and replies show `↩ #<n>`.
- **Members**: Groups helpers into **Active**, **Standing by**, and collapsed **Retired** cards, always displaying any pause detail (such as `429 Resource Exhausted`) alongside a helper's latest post preview.
- **Graph**: Shows helpers as points on a circle, a line for each pair that mention each other (the more two helpers mention each other, the thicker their line, and the line shows the count), replay controls (play/pause, step, slider, Live), and a toggle to hide inactive helpers.

## What helpers post and which tools they use

- **What helpers post**: Helpers post results, questions, and defect lists (as well as short notes) so the lead and other helpers can coordinate without losing context.
- **Tools**:
  - `post`: Writes a numbered message to the shared board.
  - `board`: Reads numbered posts from the board (filtered by recipient, author, kind, or search text).
  - `step`: Updates a helper's step count or reports a pause reason (`quota` or `error`, with optional detail).
  - `progress`: Lead-only tool used to plan tasks, move phases, accept or return work, close the flow, and `retire` or `kill` helpers.

## Waking helpers from board mentions

When a board post mentions a waiting helper (`@name`), the sidecar sends a wake straight to the helper's own conversation once for that mention (`@lead` wakes the lead conversation). Only the lead's `@all` wakes everyone who is waiting; `@all` written by a helper does not wake everyone. When a post is delivered in a wake message, it is framed and shown to other agents as helper content, never as instructions from the user, the lead, or the system.

## Member states

- `working`: Actively running its turn or waiting on its own background job.
- `waiting`: Finished its turn and standing by to be woken by an `@mention` on the board.
- `paused`: Stopped early with a pause reason (`quota` or `error`); replaces `running` with an amber `paused: <reason>` badge while the flow is open and keeps its error or quota detail visible in **Members**.
- `retired`: Done with the flow (retired by the lead via `progress` `retire`, or finished when the flow closes); listed in the **Members** tab's **Retired** group and never shown on **Flow** agent rows.
- `killed`: The lead marked the helper as killed with `progress` (`kill`). It shows a red `killed` badge and is no longer woken by board posts. This does not stop a helper that is still running; the lead stops it in the tool itself.

## Who talks to whom

The Graph tab shows helpers as points on a circle, with a line for each pair that mention each other. The more two helpers mention each other, the thicker their line, and the line shows the count. Replay controls let you review interactions over time with play/pause, step, a slider, and `Live`. `Hide inactive` hides killed or retired helpers.

## Choosing a Gemini model per task

The lead can set a model on a task and put `Gemini model: <id>` in the brief; the helper uses it instead of its default. Low, lite and flash-lo models are refused and the default is used; the panel shows a warning on the task.

## A worktree per helper

The lead can give a task its own worktree and put `Worktree: <branch>` in the brief; the helper creates it with the repo's worktree tool (or reuses it), works there, reports the path, and the panel shows it on the helper. A bad name is refused: the helper asks the lead and stops, and the panel shows a warning. Give parallel helpers on the same repository separate worktrees.

## Safety

The model and worktree are only ever read from the lead's brief, never from board posts, and are checked before use.

## Subdirectories & Verification

- Subdirectory: [lib](./lib/README.md)
- Run tests: `bazel test //apps/antigravity/plugins/vitruvian-orchestrator:panel_test`
