---
status: completed
---

# Orchestrator team file: generic roles mapped to each repo's agents

Step 1 of 5 in making `vitruvian-orchestrator` a public plugin that is useful outside
vitruvian-core while vitruvian-core keeps its tailored team. Later steps: the generic
profile of agents in the plugin (2), `/orchestrator-team init` (3), Gemini-optional
drivers (4), publishing (5). This step adds no generic agents yet.

## Roles

Ten fixed roles. The role id is lower-case and is also the name of the generic agent the
plugin will ship in step 2.

| Role | vitruvian-core agent | Default tier |
|---|---|---|
| `lead` | beacon | lead |
| `developer` | wren | build |
| `infrastructure` | atlas | build |
| `build` | forge | build |
| `operations` | ridge | build |
| `qa` | scout | deep |
| `security` | aegis | deep |
| `product` | compass | deep |
| `docs` | quill | light |
| `release` | pace | light |

## The team file: `.agents/team.json` at the repository root

Optional. JSON so every harness reads it with no dependency. Schema file:
`packages/orchestrator-core/schema/team.schema.json` (JSON Schema draft 2020-12,
`$id` `https://vitruviansoftware.dev/schemas/orchestrator-team.json`).

```json
{
  "$schema": "https://vitruviansoftware.dev/schemas/orchestrator-team.json",
  "notes": "Repo-wide notes for every specialist (build/test commands, rules).",
  "tiers": {
    "build": { "gemini": "gemini-pro-orchestrator-neon", "claude-code": "haiku", "antigravity": "pro", "opencode": "anthropic/claude-haiku-5-5", "effort": "medium" }
  },
  "roles": {
    "developer": { "agent": "wren", "tier": "build", "gemini": "gemini-4-argon-high", "notes": "Owns apps/." },
    "release": "off"
  }
}
```

Rules (enforced by the parser, mirrored in the schema):

- Top-level keys allowed: `$schema`, `notes`, `tiers`, `roles`. Anything else is an error.
- `tiers` keys: `lead`, `build`, `deep`, `light`. Each value an object with optional
  `gemini`, `claude-code`, `antigravity`, `opencode`, `effort`. Unknown keys are errors.
- `roles` keys: the ten role ids above; unknown role ids are errors. A value is either the
  string `"off"` or an object with optional `agent`, `tier`, `gemini`, `claude-code`,
  `antigravity`, `opencode`, `effort`, `notes`. Unknown keys are errors.
- `agent`: `^[a-z0-9][a-z0-9-]{0,63}$`.
- `gemini`: must pass the existing `isValidGeminiModel` in `packages/orchestrator-core/src/core.mjs`.
- Any model string containing `-low`, `-lite` or `flash-lo`, or `effort: "low"`, is an error.
  `effort` is one of `medium`, `high`, `xhigh`, `max`.
- `notes` (top level and per role): string, at most 2000 characters after
  `sanitizeDisplayText`.
- `lead` cannot be `"off"`.
- Invalid file: the parser returns errors and no team; callers fall back to no team file
  (all defaults) and surface the errors to the lead. Never throw.

## Resolution (shared core)

In `packages/orchestrator-core/src/core.mjs` (vendored into the three plugins by
`bazel run //tools/agent-roster -- --write`; never edit the vendored copies by hand):

```js
export const ROLES = ["lead","developer","infrastructure","build","operations","qa","security","product","docs","release"];
export const DEFAULT_ROLE_TIERS = { lead:"lead", developer:"build", infrastructure:"build", build:"build", operations:"build", qa:"deep", security:"deep", product:"deep", docs:"light", release:"light" };

// text: file contents or null/undefined when the file is absent.
export function parseTeam(text) // -> { team: object|null, errors: string[] }

// harness: "claude-code" | "antigravity" | "opencode"
// defaults: { tiers: { <tier>: { gemini?, <harness>?, effort? } } } — the plugin's built-in tier models.
export function resolveTeam(team, harness, defaults)
// -> { notes: string, roles: [{ role, agent, source: "team"|"generic"|"off",
//        tier, gemini, model, effort, notes }] }  in ROLES order.
```

- `agent`: the team file's `agent` if set; otherwise the role id (`source: "generic"`);
  `"off"` gives `agent: null, source: "off"`.
- `tier`: role's `tier` → `DEFAULT_ROLE_TIERS[role]`.
- `gemini` / `model` (the harness's own model) / `effort`: role override → team `tiers[tier]`
  → `defaults.tiers[tier]`. `gemini` is `null` for the `lead` tier.
- Pure functions, no file I/O in core.

## The `team` tool (all three harnesses)

A new MCP tool named `team`, no input, read-only, in:

- Claude Code: `apps/claude-code/plugins/vitruvian-orchestrator/hooks/register.tsx`
- Antigravity: `apps/antigravity/plugins/vitruvian-orchestrator/mcp/server.mjs`
- OpenCode: `apps/opencode/plugins/vitruvian-orchestrator/server.mjs`

It reads `<repo root>/.agents/team.json` (repo root = the git top-level of the session's
working directory; if not in a git repo, the working directory), runs `parseTeam` and
`resolveTeam` with that plugin's built-in tier defaults, and returns:

```json
{ "file": ".agents/team.json" | null, "errors": [], "notes": "...", "roles": [ ...resolveTeam rows ] }
```

File read errors other than "not found" go into `errors`. The file is capped at 64 KiB
(larger is an error, not read).

### Added during UAT: `root` input and the `team` flow event

- The tool takes an optional `root`, an absolute path to an existing directory, or it
  errors `root must be an absolute path to a directory`. When given, it reads
  `<root>/.agents/team.json`, and the file's real path must stay inside `root`'s real path.
  Without `root`, discovery is as above. Reason: Antigravity runs the MCP server from the
  plugin install folder and sends no workspace path, so discovery alone never finds the
  file there.
- The tool records `{ type: "team", roles: [{ agent, role }] }` (at most 10 entries,
  validated) in the flow. All three panels label agents from that event first and read the
  file only when the flow has none.
- Known risk: with `root` set to `/`, a symlinked team file is judged inside `/`. That
  needs a symlink already in place in the repository.

## The lead skill

`.agents/roster/skills/orchestrate/{claude-code,opencode,antigravity}.md` (the sources;
generated copies follow via `--write`): at the start of Plan, call the `team` tool. Route
work by role: dispatch the row's `agent`; skip roles with `source: "off"`; when the row's
`gemini` differs from that agent's built-in default, put `Gemini model: <id>` in the
brief; prepend team `notes` and the role's `notes` to the brief under "Project notes". If
`errors` is non-empty, tell the user once and continue with defaults.

## vitruvian-core's own team file

`.agents/roster/agents.tsv` gains a `role` column (values from the table above). The
generator (`tools/agent-roster`) writes `.agents/team.json` mapping every role to our
agent name, with no model overrides (our tiers already come from `tiers.tsv`). `--check`
covers it. A test fails if any mapped agent has no generated file in `.claude/agents`,
`.agents/agents` or `.opencode/agents`, or if a role is missing or duplicated in
`agents.tsv`.

## When a model change takes effect

- The Gemini model (`gemini`) takes effect on the next dispatch: the lead puts it in the
  brief as `Gemini model: <id>`, and drivers already read and validate that line.
- The harness's own model (`claude-code`, `antigravity`, `opencode`, `effort`) is read
  by each harness from the agent file when the agent loads, so it takes effect only after
  the agent files are regenerated (in vitruvian-core: `bazel run //tools/agent-roster --
  --write`; for other repos: the `sync` command planned in step 3). In step 1 the `team`
  tool reports these values; nothing applies them yet.

## Panel label

Where a member/run is shown with its agent name, show `name · role` when the agent is the
mapped agent of a role in the resolved team (for example `wren · developer`). Only the
display changes; matching and events keep using the agent name.

## Out of scope for step 1

Generic agent files, `init`, Gemini-optional drivers, publishing, site-hosting the schema.
