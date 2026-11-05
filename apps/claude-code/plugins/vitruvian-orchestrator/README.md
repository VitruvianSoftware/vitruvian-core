# vitruvian-orchestrator (Claude Code)

Claude Code plugin for routing multi-domain engineering work across the Vitruvian specialist subagent roster with a live orchestration panel and above-prompt status band.

## What is in this plugin

- **`orchestrate` lead skill (`skills/orchestrate/SKILL.md`)**: Generated from `.agents/roster/` by `//tools/agent-roster`. Turns the active Claude Code session into the lead orchestrator that plans across five phases (`plan` → `design` → `delegate` → `review` → `close`), dispatches tasks to specialist subagents using the Claude Code model and effort ladder (`lead`, `core`, `fast`), routes bulk work off Claude tokens via `agy-delegate`, and reviews diffs adversarially.
- **Specialist subagents**: Live in the repository's `.claude/agents/*.md` (also generated from `.agents/roster/`), where Claude Code loads them automatically for the project.
- **Live orchestration panel (`hooks/register.tsx`)**: A Claude Code mod that renders a live `Orchestrator` pane (`id: "vitruvian-orchestrator"`) and an `AbovePrompt` status band on both terminal and desktop surfaces, backed by the vendored `hooks/lib/orchestrator-core.mjs` state machine:
  1. **Header**: Flow title, phase pills (`plan`, `design`, `delegate`, `review`, `close` with muted checks for completed phases and highlighted active phase), `"accepted N of M"`, and estimated cost so far (`est.`).
  2. **Burn-down**: Remaining unaccepted tasks over time with a dashed ideal line and re-plan markers (rendered as an SVG chart on desktop and a one-line text sparkline on terminal).
  3. **Task board**: One row per planned task showing `#n`, title, specialist, tier, status (`waiting`, `ready`, `running`, `review`, `returned`, `accepted`), return round, and `"waits on #x"` when blocked on dependencies.
  4. **Agents**: One row per run (lead and subagent workers) showing the agent name and chibi mascot (on desktop), full model ID, effort, step progress (`done/total`) or context window percentage, token count, estimated cost (`est.`) or `unpriced`, elapsed time, and run status.
  5. **Spend**: Estimated spend split between `lead` and `workers`, per-model breakdown, and unpriced runs reported by token count rather than dollars.
  - **AbovePrompt band**: Appears once a flow exists, showing `title · phase · N of M accepted` and a crew-size button (`×N`) that opens the `Orchestrator` pane. The pane auto-opens once per flow when the first plan arrives.

## Tools and commands

- **`mcp__vitruvian-orchestrator__progress`** (registered as `progress`): Called by the lead orchestrator to create or re-plan tasks (`title`, `tasks`), transition `phase` (`plan`, `design`, `delegate`, `review`, `close`), `accept` or `return` a 1-based task number after review, and mark the flow `finished`.
- **`mcp__vitruvian-orchestrator__step`** (registered as `step`): Called by a worker subagent to report its own step progress (`done`, `total`, `note`), matched automatically to the calling subagent's `agentId`.
- **`/orchestrator`**: Slash command that toggles the `Orchestrator` live pane open or closed.

## Attribution

The subagent lifecycle hooks, above-prompt progress band, and pane rendering mechanics in `hooks/register.tsx` are adapted from [`savvy-progress`](https://github.com/johnnyvizz/claude-kit/tree/main/plugins/savvy-progress) by `johnnyvizz` (`johnnyvizz/claude-kit`, MIT License — see [`LICENSE-THIRD-PARTY`](./LICENSE-THIRD-PARTY)), combined with James Nguyen's custom 30×28 anime-style chibi specialist mascots (`MASCOTS`).

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
