---
status: completed
---

# Orchestrator: generic agents that work without Gemini (step 4 of 5)

Step 4 of 5 in making `vitruvian-orchestrator` a public plugin (step 1: team file, #5223;
step 2: generic team, #5228). Today every generic Claude Code and OpenCode agent is a Haiku
driver with no editing tools that hands its work to Gemini through `agy-delegate`. A user
without Antigravity gets agents that can do nothing. This step makes the generic agents do
the work themselves by default, and keeps Gemini as an opt-in.

vitruvian-core's own named agents (wren, scout, …) do not change: they stay Gemini drivers
with no editing tools.

## The engine

Each role now has an **engine**:

- `native` (default): the agent does the work itself on its harness model.
- `gemini`: the agent is a driver. It hands the work to Gemini with `agy-delegate`, checks it
  and reports, exactly as today.

In Antigravity the engine is always `native`, because there the agent already runs on Gemini.

### Team file

`engine` (`"native"` or `"gemini"`) may be set at three levels; the most specific wins:
role, then tier, then the top level. Absent everywhere: `native`.

```json
{ "engine": "gemini", "tiers": { "light": { "engine": "native" } } }
```

The schema gains `engine` on the top level, `tierConfig` and `roleConfig`. Any other value is
a schema error; `resolveTeam` ignores a non-string or unknown value (falls through to the next
level), the same way it treats other bad values.

vitruvian-core's generated `.agents/team.json` gets top-level `"engine": "gemini"`, so its
resolved rows say what its named agents really do.

### Resolved row

`resolveTeam` rows gain `engine`. The row `model` now depends on it:

- a team-file harness model (role, then tier) always wins;
- otherwise `engine: "gemini"` gives the **driver** default (Claude Code `haiku`, OpenCode
  `anthropic/claude-haiku-5-5`, effort `medium`), and `engine: "native"` gives the **native**
  default (table below).
- Off rows: `engine: null`. Lead row: `engine: "native"`, models unchanged.
- A row mapped to the repository's own agent (`source: "team"`) with no engine set at any
  level: `engine: null` ("its own file decides"), and `model`/`effort` only from an explicit
  team-file value, else `null` (the lead passes no override, so the agent file's frontmatter
  wins). An explicit engine on such a row is returned as-is; its model still follows the
  explicit-or-null rule. Its fallback when Gemini is blocked is the role's generic agent
  with `Engine: native`, since a mapped agent may have no native mode (review round 1).

### Native defaults (`.agents/roster/generic/tiers.tsv`, new)

| Tier | Claude Code | OpenCode | Effort |
|---|---|---|---|
| build | sonnet | (session model) | high |
| deep | sonnet | (session model) | high |
| light | sonnet | (session model) | medium |

OpenCode's "session model" is `null` in the row and no `model:` line in the agent file, so a
stranger's OpenCode uses whatever provider they already run. Claude Code has no such
"cheaper than the lead" inherit, so it names `sonnet`. Never low effort, never a lite model;
the generator validates this file with the same rules as `tiers.tsv`.

`tier-defaults.mjs` (per plugin) gains a `native` object per non-lead tier with these
values; the existing keys stay the driver defaults.

## Generic agent files (Claude Code and OpenCode)

- Frontmatter uses the native defaults: Claude Code `model: sonnet` + effort; OpenCode no
  `model` (and no `reasoningEffort`).
- Tools: the driver tools **plus editing** (Claude Code adds `Edit, Write`; OpenCode drops
  the `write/edit/patch: false` block).
- Body: one "How you run a task" that starts by choosing the mode:
  1. Save the lead prompt to `"$LEAD"` first (unchanged). Read `Engine:` only from
     `"$LEAD"`, first match at line start, exactly `gemini` or `native`; anything else is
     `native`.
  2. If `Engine: gemini` **and** `command -v agy-delegate` succeeds: **Gemini mode**, the
     current driver steps, and the agent must not edit files itself in this mode.
  3. Otherwise **native mode**: do the task yourself following "Your role", in the same
     worktree/channel handling (`Worktree:`, `Channel:` validated from `"$LEAD"` as today),
     then check your own diff, run the brief's verification, post to the board and report
     as today. Report `step` without `delegate`. If the brief asked for Gemini but
     `agy-delegate` is missing, say in the report that it ran natively and why.
  4. Review-only briefs (no file changes) stay review-only in both modes.
- Project profile agents (`.claude/agents`, `.opencode/agents`) are unchanged.

## Lead skill (all three harness sources in `.agents/roster/skills/orchestrate/`)

- Replace "each specialist is a Haiku driver…" with: each role's `engine` from the `team`
  tool says how it runs; `gemini` roles are cheap drivers that hand work to Gemini, `native`
  roles do the work on their own model.
- Dispatch: for an `engine: "gemini"` row put `Engine: gemini` in the brief (plus
  `Gemini model:` when overridden). In Claude Code pass the row's `model` as the Agent
  tool's `model` (so a generic agent in Gemini mode runs on the cheap driver model).
- Fallback: a `BLOCKED` Gemini-mode specialist is retried once, then re-dispatched to the
  **same role** with `Engine: native` (no `general-purpose` hop). Never move specialist work
  to the lead model.
- Tiers section: describe both engines; no claim that every specialist runs on Gemini.

## Tests

- core: engine precedence (role > tier > top > default), bad values ignored, Antigravity
  always native, model picks driver vs native default, explicit harness model wins in both
  engines, off/lead rows.
- schema: `engine` accepted at the three levels; other values rejected.
- generator: generic Claude Code/OpenCode agents have editing tools, both modes, `Engine:`
  read only from `"$LEAD"`; project agents still have no editing tools and no native mode;
  `generic/tiers.tsv` validation rejects low/lite; `team.json` carries `"engine": "gemini"`.
- plugin `team` tool output includes `engine` in all three plugins.

## Out of scope

`init`/`sync` writing models into agent files (step 3), publishing (step 5).
