# vitruvian-orchestrator (Claude Code)

Claude Code plugin for routing multi-domain engineering work across the Vitruvian specialist subagent roster.

## What is in this plugin today

- **`orchestrate` lead skill (`skills/orchestrate/SKILL.md`)**: Generated from `.agents/roster/` by `//tools/agent-roster`. Turns the active Claude Code session into the lead orchestrator that plans across five phases (`plan` → `design` → `delegate` → `review` → `close`), dispatches tasks to specialist subagents using the Claude Code model and effort ladder (`lead`, `core`, `fast`), routes bulk work off Claude tokens via `agy-delegate`, and reviews diffs adversarially.
- **Specialist subagents**: Live in the repository's `.claude/agents/*.md` (also generated from `.agents/roster/`), where Claude Code loads them automatically for the project.

## What is coming next

- **Live orchestration panel (`hooks/register.tsx`)**: A Claude Code mod displaying the active flow header, task burn-down chart, task board with return rounds, live subagent progress/context telemetry, and estimated token spend per model, backed by the shared `packages/orchestrator-core` package.

## Install

Add this repository's plugin marketplace in Claude Code, then install `vitruvian-orchestrator`:

```bash
claude plugin marketplace add VitruvianSoftware/vitruvian-core
claude plugin install vitruvian-orchestrator@vitruvian-core
```

Or from a local checkout of `vitruvian-core`:

```bash
claude plugin marketplace add .
claude plugin install vitruvian-orchestrator@vitruvian-core
```
