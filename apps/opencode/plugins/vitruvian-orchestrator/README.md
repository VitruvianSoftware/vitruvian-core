# Vitruvian Orchestrator — OpenCode Live Panel

OpenCode plugin for the `orchestrate` workflow. It registers the orchestration tools, watches helper sessions, wakes waiting helpers when they are mentioned on the board, and renders a live **Orchestrator** sidebar in the OpenCode TUI.

## What the sidebar shows

1. **Header**: Flow title, five phase pills (`plan`, `design`, `delegate`, `review`, `close`), accepted task count (`accepted N of M`), and estimated spend (`est. $X.XX`).
2. **Burn-down**: Compact sparkline of remaining tasks over time against the ideal line, plus re-plan markers (`⟳`).
3. **Tasks**: Numbered tasks with title, `[specialist/tier]`, state, return round, and dependency badges (`waits on #x`).
4. **Agents**: One row per lead or helper run showing model, effort, step count or context usage, tokens, estimated cost, elapsed time, and run status (`running`, `done`, `error`, amber `paused: <reason>` in place of `running`, or red `killed`). Open and closed flows with no board posts and no pause/kill events look identical to classic flows.
5. **Spend**: Lead vs. worker spend, per-model spend, and unpriced token counts.
6. **Overview** (shown when non-empty once the flow has board posts or a non-`main` channel): Short summary of only non-empty parts — active/standing-by helpers, open questions, open defects, and quiet or stalled helpers.
7. **Board** (hidden until the first post): Newest five numbered posts (`#1`, `#2`, …) with sender, recipients (`@all` shown as `everyone`), reply tag (`↩ #<n>`), channel tag (`#<channel>` when not `main`), age, kind badge, and single-line summary.

When no plan has been reported yet, the sidebar shows:
`Orchestrator panel fills in when the lead skill reports a plan.`

## Shared board, tools, waking, and member states

- **What the board is**: The board is a shared message list for the helpers and the lead, kept as numbered posts so everyone can follow the conversation in order.
- **What helpers post**: Helpers post results, questions, and defect lists (along with brief notes).
- **Tools**:
  - `post`: Posts a message to the board (`text`, optional `to`, `kind`, `replyTo`, and `channel`).
  - `board`: Reads numbered posts from the board (`to`, `from`, `kind`, `channel`, `search`, `limit`). When a helper omits `to` or passes `to: "me"`, it receives posts addressed to that helper or to everyone.
  - `channel`: Lists channels (`action: "list"`, open to all) or creates and archives channels (`action: "create"` or `"archive"`, lead-only, up to 20 channels).
  - `step`: Called by a helper to report step progress (`done`, `total`, `note`) or a pause reason (`paused: "quota"` or `paused: "error"`, plus optional `detail`).
  - `progress`: Called only by the lead to create or update the plan, advance phases, accept or return tasks, close the flow, or `retire` / `kill` a helper.
- **How waking works**: Mentioning a waiting helper (`@name`) sends the post straight to the helper's own conversation once for that mention (`@lead` wakes the lead conversation). Only the lead's `@all` wakes everyone who is waiting; a helper's `@all` never wakes everyone. Each woken post is clearly labeled and shown to other agents as helper content, never as instructions from the user, the lead, or the system.
- **Member states**:
  - `working`: Actively running its turn or delegated task.
  - `waiting`: Finished its turn and standing by so an `@mention` on the board can wake it.
  - `paused`: Stopped early with a pause reason (`quota` or `error`); shown on the helper's row in amber (`paused: quota` or `paused: error`) in place of `running` while the flow is open.
  - `retired`: Finished for good — either retired by the lead with `progress` (`retire`) or when the flow closes. Retired helpers are no longer woken by mentions, and `retired` is never shown on agent run rows.
  - `killed`: The lead marked the helper as killed with `progress` (`kill`). It shows a red `killed` badge and is no longer woken by board posts. This does not stop a helper that is still running; the lead stops it in the tool itself.

## Who talks to whom

The sidebar displays a one-line list of the top five pairs (for example, `scout → wren ×4`), shown only when posts mention someone.

## Choosing a Gemini model per task

The lead can set a model on a task and put `Gemini model: <id>` in the brief; the helper uses it instead of its default. Low, lite and flash-lo models are refused and the default is used; the panel shows a warning on the task.

## A worktree per helper

The lead can give a task its own worktree and put `Worktree: <branch>` in the brief; the helper creates it with the repo's worktree tool (or reuses it), works there, reports the path, and the panel shows it on the helper. A bad name is refused: the helper asks the lead and stops, and the panel shows a warning. Give parallel helpers on the same repository separate worktrees.

## Overview

The sidebar's **Overview** section gives a short data-only summary and shows only non-empty parts: active and standing-by helpers (one row per helper from its latest run, showing its latest step note or else its latest post), open questions (questions with no later `replyTo` answer), open defects, and quiet or stalled runs. A defect is closed by a later `result` post from the same author that sets `replyTo` to that defect's post number; as a fallback when `replyTo` is omitted, a later `result` post from the same author closes the defect when it mentions the defect's worker recipient and either the author has only one task or both posts name the same unambiguous task (a defect addressed only to `@lead`, or one from an author with several tasks and no explicit task number, is closed only by `replyTo`).

## Channels

Posts belong to a channel (`main` by default; channel names match `[a-z0-9][a-z0-9-]{0,31}`, up to 20 channels). Only the lead can create or archive channels with `channel`; everyone can list channels, filter `board` by `channel`, and post to open channels. Posting to an unknown or archived channel fails with an error, and `main` cannot be archived. When the lead puts `Channel: <name>` in a task brief, the helper posts in that channel.

## Safety

The model, worktree, and channel are only ever read from the lead's brief, never from board posts, and are checked before use.

## Setup and verification

- **In this repository**: OpenCode automatically loads `.opencode/plugins/vitruvian-orchestrator/` when started from the repository root.
- **Outside this repository**: Run `./apps/opencode/plugins/vitruvian-orchestrator/install.sh` to install the loader files into `~/.config/opencode/plugins/vitruvian-orchestrator/`.
- **Subdirectory**: [lib](./lib/README.md)
- **Verification**: `bazel test //apps/opencode/plugins/vitruvian-orchestrator/...`
