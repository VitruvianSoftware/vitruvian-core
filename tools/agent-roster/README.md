# `//tools/agent-roster`

Generates per-harness agent files for Claude Code (`.claude/agents/*.md`), Antigravity (`.agents/agents/*.md`), and OpenCode (`.opencode/agents/*.md`) and each harness's `orchestrate` lead skill (`SKILL.md`) from the single roster under `.agents/roster/`.

## Commands

```sh
# Check that all generated agent files match .agents/roster/ byte-for-byte (default):
bazel run //tools/agent-roster -- --check

# Regenerate all agent files and remove any unlisted .md files in the output folders:
bazel run //tools/agent-roster -- --write
```

`bazel run //:tidy` runs `//tools/agent-roster:write` before Gazelle and the formatters, so CI's Tidy Check fails when generated agent files drift from `.agents/roster/`.

## Rules enforced

- **Agent names**: `^[a-z][a-z0-9-]*$`, unique, with a non-empty prompt at `.agents/roster/prompts/<name>.md` and a tier defined for all three harnesses in `.agents/roster/tiers.tsv`.
- **Descriptions**: single-line, non-empty, at most 320 characters (Antigravity silently drops longer descriptions), no `: ` (colon-space), and no leading `#` or quote character.
- **Never low effort**: `low` effort is rejected on every tier and harness.
- **Per-harness models and effort**:
  - Antigravity: `model` in `{inherit, flash, pro}`, `effort` must be `-`.
  - Claude Code: `model` in `{inherit, opus, sonnet, haiku, fable}` or `claude-*`, `effort` in `{-, medium, high, xhigh, max}`.
  - OpenCode: `model` matching `provider/model` (`^[a-z0-9-]+/[A-Za-z0-9._-]+(#[a-z]+)?$`), `effort` in `{-, medium, high, xhigh, max}` (written as `reasoningEffort`).

## Lead skill (`orchestrate`)

Reads `.agents/roster/skills/orchestrate/{claude-code,antigravity,opencode}.md`, checks that each template has YAML frontmatter with `name: orchestrate`, a valid `description:` (<= 320 chars), and exactly one `<!-- roster:table -->` line, and writes:

- `apps/claude-code/plugins/vitruvian-orchestrator/skills/orchestrate/SKILL.md`
- `apps/desktop/antigravity/plugins/vitruvian-orchestrator/skills/orchestrate/SKILL.md`
- `.opencode/skills/orchestrate/SKILL.md`

Each `SKILL.md` gets the generated header comment after its frontmatter and a harness-specific `| Agent | Tier | Model | Routing rule |` table in `agents.tsv` order.
