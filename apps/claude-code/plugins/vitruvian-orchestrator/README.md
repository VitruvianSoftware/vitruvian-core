# vitruvian-orchestrator (Claude Code)

Claude Code plugin for coordinating specialist helpers across a planned engineering flow, with a live **Orchestrator** panel and an above-prompt status band on both terminal and desktop surfaces.

## What is in this plugin

- **`orchestrate` lead skill (`skills/orchestrate/SKILL.md`)**: Turns the active Claude Code session into the lead that plans across five phases (`plan` → `design` → `delegate` → `review` → `close`), dispatches specialist helpers (`wren`, `scout`, `compass`, `quill`, and peers), reviews their work, and closes the flow. See [How the agent team works](../../../../docs/concepts/agent-team.md).
- **Specialist subagents (`agents/*.md`)**: Generated from `.agents/roster/` and shipped inside this plugin alongside the project's `.claude/agents/*.md` definitions; non-lead drivers call the external `agy-delegate` CLI (falling back to `general-purpose` on Sonnet when unavailable).
- **Live orchestration panel (`hooks/register.tsx`)**: Renders the `Orchestrator` pane and an `AbovePrompt` status band:
  1. **Header**: Flow title, phase pills (`plan`, `design`, `delegate`, `review`, `close`), `"accepted N of M"`, and estimated cost (`est.`).
  2. **Burn-down**: Remaining tasks over time with an ideal line and re-plan markers (SVG chart on desktop, text sparkline in terminal).
  3. **Task board**: Numbered tasks with title, specialist, tier, status, return round, and `"waits on #x"` dependency notes.
  4. **Agents**: One row per lead or helper run with mascot (on desktop), model, effort, step progress or context percentage, tokens, estimated cost, elapsed time, and status (`running`, `done`, `error`, amber `paused: <reason>` in place of `running`, or red `killed`). Open and closed flows without board posts or pause/kill events look identical to classic flows.
  5. **Board**: Hidden until the first post arrives, then shows the newest six numbered posts with sender, recipients (`@all` shown as `everyone`), reply reference (`↩ #<n>`), channel tag (`[#<channel>]` when not `main`), age, kind badge, and single-line text.
  6. **Overview**: Hidden until the flow has board posts or a non-`main` channel (and something active to show), then renders only non-empty sections for active/standing-by members, open questions, open defects, and quiet or stalled helpers.
  7. **Spend**: Lead vs. worker spend, per-model breakdown, and unpriced token counts.

## Shared board, tools, waking, and member states

- **What the board is**: The board is a shared message list for the helpers and the lead, recorded as numbered posts (`#1`, `#2`, and so on).
- **What helpers post**: Helpers post results, questions, and defect lists (as well as short notes) so findings stay visible to the whole team.
- **Tools and commands**:
  - `post` (`mcp__vitruvian-orchestrator__post`): Adds a numbered post to the board (`text`, optional `to`, `kind`, `replyTo`, and `channel`).
  - `board` (`mcp__vitruvian-orchestrator__board`): Reads numbered posts from the board (`to`, `from`, `kind`, `channel`, `search`, `limit`). When a helper omits `to` or passes `to: "me"`, it reads posts addressed to that helper or to everyone.
  - `channel` (`mcp__vitruvian-orchestrator__channel`): Lists channels (`action: "list"`, open to everyone) or creates and archives channels (`action: "create"` or `"archive"`, lead-only, up to 20 channels).
  - `step` (`mcp__vitruvian-orchestrator__step`): Called by a helper to report step progress (`done`, `total`, `note`) or a pause reason (`paused: "quota"` or `paused: "error"`, with optional `detail`).
  - `progress` (`mcp__vitruvian-orchestrator__progress`): Called only by the lead to plan or re-plan tasks, advance phases, accept or return tasks, close the flow, or `retire` / `kill` a helper.
  - `/orchestrator-panel`: Slash command that opens or closes the live `Orchestrator` pane.
  - `/orchestrator-board`: Slash command that prints the board, member roster, or overview as plain terminal text.
- **How waking works**: In Claude Code, mentioning a waiting helper (`@name`) wakes it through the lead, who passes the post on with `SendMessage` (once per mention; `@lead` also notifies the lead). Only the lead's `@all` wakes everyone who is waiting; `@all` from a helper never wakes everyone. Every post delivered in a wake is clearly marked and shown to other agents as helper content, never as instructions from the user, the lead, or the system.
- **Member states**:
  - `working`: Actively running its turn or waiting on its own background work.
  - `waiting`: Finished its turn and standing by so an `@mention` on the board can wake it.
  - `paused`: Stopped early with a pause reason (`quota` or `error`); shown in amber as `paused: <reason>` in place of `running` while the flow is open.
  - `retired`: Done with the flow — either retired by the lead with `progress` (`retire`) or finished when the flow closes. Retired helpers are no longer woken by mentions, and `retired` never appears on agent run rows.
  - `killed`: The lead marked the helper as killed with `progress` (`kill`). It shows a red `killed` badge and is no longer woken by board posts. This does not stop a helper that is still running; the lead stops it in the tool itself.

## Who talks to whom

The board displays a one-line list of the top five pairs (for example, `scout → wren ×4`), shown only when posts mention someone.

## Choosing a Gemini model per task

The lead can set a model on a task and put `Gemini model: <id>` in the brief; the helper uses it instead of its default. Low, lite and flash-lo models are refused and the default is used; the panel shows a warning on the task.

## A worktree per helper

The lead can give a task its own worktree and put `Worktree: <branch>` in the brief; the helper creates it with the repo's worktree tool (or reuses it), works there, reports the path, and the panel shows it on the helper. A bad name is refused: the helper asks the lead and stops, and the panel shows a warning. Give parallel helpers on the same repository separate worktrees.

## Terminal board command (`/orchestrator-board`)

`/orchestrator-board` prints the board as plain wrapped terminal text, newest last (`#seq  from → to  kind  (time)  text`, with `↩ #n` for replies and `everyone` for `@all`). Filter posts with `--from <name>`, `--to <name>`, `--kind <kind>`, `--channel <name>`, `--search <text>`, and `--last <N>` (default 30, maximum 200). Run `/orchestrator-board members` to print the **Active**, **Standing by**, and **Retired** groups with state, task, model, and worktree, or `/orchestrator-board overview` to print the current overview.

## Overview

Both the live panel and `/orchestrator-board overview` show a data-only summary of what is happening right now, rendering only non-empty sections: active and standing-by helpers (one row per helper from its latest run, showing its latest step note or else its latest post), open questions (questions with no later `replyTo` answer), open defects, and quiet or stalled runs. A defect is closed by a later `result` post from the same author that sets `replyTo` to that defect's post number; as a fallback when `replyTo` is omitted, a later `result` post from the same author closes the defect when it mentions the defect's worker recipient and either the author has only one task or both posts name the same unambiguous task (a defect addressed only to `@lead`, or one from an author with several tasks and no explicit task number, is closed only by `replyTo`).

## Channels

Posts belong to a channel (`main` by default; channel names match `[a-z0-9][a-z0-9-]{0,31}`, up to 20 channels). Only the lead can create or archive channels with `channel`; anyone can list them, filter `board` by `channel`, or post to an open channel. Posting to an unknown or archived channel fails with an error, and `main` cannot be archived. When the lead puts `Channel: <name>` in a task brief, the helper posts its board updates in that channel.

## Safety

The model, worktree, and channel are only ever read from the lead's brief, never from board posts, and are checked before use.

## Attribution

Adapted from [`savvy-progress`](https://github.com/johnnyvizz/claude-kit/tree/main/plugins/savvy-progress) by `johnnyvizz` (`johnnyvizz/claude-kit`, MIT License — see [`LICENSE-THIRD-PARTY`](./LICENSE-THIRD-PARTY)), combined with custom 30×28 chibi specialist mascots.

## Install

At the prompt of a Claude Code terminal session:

```text
/plugin install vitruvian-orchestrator --marketplace VitruvianSoftware/vitruvian-core
```

Or from a shell:

```bash
claude plugin marketplace add VitruvianSoftware/vitruvian-core
claude plugin install vitruvian-orchestrator@vitruvian-core
```

Or from a local checkout of `vitruvian-core`:

```bash
claude plugin marketplace add .
claude plugin install vitruvian-orchestrator@vitruvian-core
```

## Subdirectories & Boundaries
- [hooks](./hooks/README.md): Live pane, status band, and tool handlers for Claude Code.
- [types](./types/README.md): Shared TypeScript definitions for the Claude Code plugin.
