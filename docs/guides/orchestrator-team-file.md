# Configure your orchestrator team

An optional `.agents/team.json` file at the repository root tells the `vitruvian-orchestrator` lead which of your agents fills each role, which models they use, and what project notes to include in every task brief. Without this file, the lead uses built-in generic role names and default tier models. You can start with nothing, add only repo-wide notes, or map specific roles to your own agents.

## The ten roles

The orchestrator routes work across ten fixed roles. When you do not map a role to a custom agent, it uses the plugin's generic agent for that role (`source: "generic"`).

| Role | What it does | Default tier |
|---|---|---|
| `lead` | Plans the work, dispatches specialists, and reviews the result | `lead` |
| `developer` | Writes and updates application code | `build` |
| `infrastructure` | Manages cloud and platform infrastructure | `build` |
| `build` | Maintains build configuration and toolchains | `build` |
| `operations` | Handles cluster operations, deployments, and incident triage | `build` |
| `qa` | Tests changes, checks edge cases, and flags defects | `deep` |
| `security` | Reviews changes for security risks and vulnerabilities | `deep` |
| `product` | Checks acceptance criteria and user-facing behavior | `deep` |
| `docs` | Writes and updates documentation | `light` |
| `release` | Handles release readiness and sequencing | `light` |

In `vitruvian-core`, these ten roles map to `beacon`, `wren`, `atlas`, `forge`, `ridge`, `scout`, `aegis`, `compass`, `quill`, and `pace`. Those names are just one repository's mapping, not defaults for other repositories.

## The generic team

The `vitruvian-orchestrator` plugin ships ten role-named agents (`lead`, `developer`, `infrastructure`, `build`, `operations`, `qa`, `security`, `product`, `docs`, `release`) so orchestration works in any repository without custom agent definitions. Each generic agent reads the repository's own instructions (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README`) first and falls back to standard ecosystem commands when none are specified.

When a role has no mapping in `.agents/team.json` (`source: "generic"`), it uses its generic agent:

- **Claude Code:** `vitruvian-orchestrator:<role>` (plugin agents are namespaced).
- **Antigravity and OpenCode:** `<role>`.

The `team` tool's `dispatch` field on each role row gives the exact agent id to start: `agent` when `source` is `"team"`, the generic agent id above when `source` is `"generic"`, and `null` when `source` is `"off"`.

## Three levels of setup

### 1. Nothing (generic team)

You do not need a `.agents/team.json` file at all. Leaving the file out — or starting with an empty object — tells the lead to use the generic role IDs and built-in tier defaults:

```json
{}
```

### 2. Notes only

Add a top-level `notes` field to give every specialist your build, test, and repo rules. The lead prepends these notes under **Project notes** in each task brief:

```json
{
  "$schema": "https://vitruviansoftware.dev/schemas/orchestrator-team.json",
  "notes": "Run `pnpm test` before finishing. Never edit generated files under dist/."
}
```

### 3. Map roles to your own agents

Map any role under `roles` to an agent name in your repository, optionally override its tier or model, or add role-specific notes:

```json
{
  "$schema": "https://vitruviansoftware.dev/schemas/orchestrator-team.json",
  "notes": "Run `npm test` after every change.",
  "roles": {
    "developer": { "agent": "coder", "notes": "Owns src/." },
    "qa": { "agent": "reviewer", "tier": "deep" },
    "release": "off"
  }
}
```

## Engine

Each role resolves an `engine`: `"native"` (default) or `"gemini"`.

- **`native` (default):** the specialist does the work itself on its own harness model.
- **`gemini`:** the specialist is a driver that hands the task to Gemini via `agy-delegate`, checks the result, and reports back.

In Antigravity, the engine is always `"native"` because the agent already runs on Gemini.

A role mapped to your own agent (`roles.<role>.agent`) with no `engine` set anywhere resolves to `engine: null`: your agent's own file decides how it runs, and the lead passes no model override unless the team file sets one. `native` and `gemini` defaults apply to the plugin's generic agents.

You can set `engine` at three levels. The most specific value wins:

1. Role (`roles.<role>.engine`)
2. Tier (`tiers.<tier>.engine`)
3. Top level (`engine`)
4. Default (`"native"` when absent everywhere)

Non-string or unknown values are schema errors; `resolveTeam` ignores them and falls through to the next level.

```json
{ "engine": "gemini", "tiers": { "light": { "engine": "native" } } }
```

In `vitruvian-core`, the generated `.agents/team.json` sets top-level `"engine": "gemini"` so its named agents continue running as Gemini drivers.

### Engine model defaults

A team-file harness model (`roles.<role>` or `tiers.<tier>`) always wins. Otherwise, the resolved row's `model` and `effort` depend on `engine`:

- When `engine` is `"gemini"`, the row uses the driver default: `haiku` in Claude Code, `anthropic/claude-haiku-5-5` in OpenCode, at `medium` effort.
- When `engine` is `"native"`, generic agents use these native defaults:

| Tier | Claude Code | OpenCode | Effort |
|---|---|---|---|
| `build` | `sonnet` | `(session model)` | `high` |
| `deep` | `sonnet` | `(session model)` | `high` |
| `light` | `sonnet` | `(session model)` | `medium` |

`(session model)` means no `model` is set (`null` in the resolved row and no `model:` line in the generic OpenCode agent file), so OpenCode uses the user's own session provider. Low effort and lite models are never used.

For the `lead` role, `engine` is always `"native"`. For `"off"` roles, `engine` is `null`.

## Models

You can set models per tier under `tiers` or per role under `roles`. For `gemini`, the active harness's own model (`claude-code`, `antigravity`, or `opencode`), and `effort`, the lead resolves each setting in this order:

1. Role override (`roles.<role>.<key>`)
2. Team tier setting (`tiers.<tier>.<key>`)
3. The plugin's built-in tier default (based on `engine` for harness models)

For the `lead` tier, `gemini` always resolves to `null`.

- **Low-power models are rejected.** Any model string containing `-low`, `-lite`, or `flash-lo` is invalid. Setting `effort` to `"low"` is also rejected; valid `effort` values are `"medium"`, `"high"`, `"xhigh"`, and `"max"`.

### When a model change takes effect

- **The Gemini model (`gemini`) takes effect on the next dispatch:** the lead puts it in the brief as `Gemini model: <id>`, and drivers already read and validate that line.
- **The harness's own model and effort (`claude-code`, `antigravity`, `opencode`, `effort`) take effect only after the agent files are regenerated or synced:** each harness reads these values from the agent file when the agent loads (in `vitruvian-core`: `bazel run //tools/agent-roster -- --write`; in other repositories: run `team_setup` with `action: "sync"`, or invoke the `team-setup` skill). In Claude Code the lead also passes the row's `model` to the Agent tool at dispatch, so it applies to the next run even before a sync; Antigravity and OpenCode read it only from the agent file.

## Turning a role off

Set a role's value to `"off"` when your repository does not use it:

```json
{
  "roles": {
    "infrastructure": "off",
    "release": "off"
  }
}
```

The lead skips any role whose resolved `source` is `"off"`. You cannot turn `lead` off.

## Checking your setup

Call the read-only `team` MCP tool (available in Claude Code, Antigravity, and OpenCode) to see what the lead sees. Pass `root`, the absolute path of your repository. The lead skill does this for you. Antigravity runs the plugin from its own install folder and doesn't tell it which repository you're in, so without `root` it can't find your file. A `root` that isn't an absolute path to a directory is rejected with `root must be an absolute path to a directory`. Without `root`, the tool falls back to the session's working directory and its git repository root. It reads `<root>/.agents/team.json` and returns:

- `file`: `".agents/team.json"` whenever the file is found (including when it has errors), or `null` only when it is absent.
- `errors`: Any parse, validation, symlink, size-limit, or file-read errors (a missing file is not an error).
- `notes`: The resolved top-level notes.
- `roles`: The resolved list of all ten roles in order (`lead`, `developer`, `infrastructure`, `build`, `operations`, `qa`, `security`, `product`, `docs`, `release`), showing each role's `agent`, `dispatch`, `source`, `tier`, `engine`, `gemini`, `model`, `effort`, and `notes`.

`.agents/team.json` may be a symlink, as long as its real target is inside the repository:

- A symlink that points outside the repository reports `.agents/team.json must be inside the repository`.
- A dangling symlink (whose target does not exist) is an error, never a missing file. Antigravity and OpenCode report an error starting with `.agents/team.json is a dangling symlink`. Claude Code reports `.agents/team.json must be inside the repository or readable` for any link it cannot resolve.
- Malformed JSON reports an error starting with `invalid JSON:`.
- A file larger than 64 KiB is not read and reports a size-limit error.

If `.agents/team.json` is larger than 64 KiB, is a symlink pointing outside the repository, is a dangling symlink, has malformed JSON, or contains any invalid key or value, the file is not used: every role falls back to defaults, and the lead surfaces `errors` to you once and continues with defaults.

## Set it up and keep it in sync

Use the `team-setup` skill or call the `team_setup` MCP tool (pass `root` as the absolute repository path) to create your starter team file or copy its model settings into your repository's agent files.

### `init`: create a starter setup

`team_setup` with `action: "init"` creates `.agents/team.json` with `$schema`, an empty `notes` string, and empty `roles` (so every role starts on the plugin's generic agent). It never overwrites existing files.

- Pass `agents: ["developer", ...]` (any role except `lead`) to copy those roles' generic agents into the calling harness's agent folder as `team-<role>.md` (`.claude/agents/`, `.agents/agents/`, or `.opencode/agents/`), rewrite `name:`, and map each role in `.agents/team.json` with `"agent": "team-<role>"` and `"engine": "native"`.
- If `.agents/team.json` or any requested `team-<role>.md` file already exists, `init` refuses and writes nothing (all-or-nothing).
- After `init`, edit `.agents/team.json` and run `sync` to apply your model settings.

### `sync`: apply models to agent files

`team_setup` with `action: "sync"` updates model and effort lines in your repository's own agent files for every role with `source: "team"`. It reads only explicit harness values from `.agents/team.json` (role setting, then tier setting) and never writes plugin defaults:

| Harness | Agent file | Frontmatter lines updated |
|---|---|---|
| Claude Code | `.claude/agents/<agent>.md` | `model:`, `effort:` |
| OpenCode | `.opencode/agents/<agent>.md` | `model:`, `reasoningEffort:` |
| Antigravity | `.agents/agents/<agent>.md` | `model:` (`inherit`, `flash`, or `pro` only) |

- **Edits stay minimal:** Only those YAML frontmatter lines change; missing keys are added at the end of frontmatter, and the body and all other keys stay byte-identical.
- **Safe skips:** Sync skips and reports files with a `"Generated by ... Do not edit"` header comment, files without YAML frontmatter, symlinks, paths outside the repository, and Antigravity values other than `inherit`, `flash`, or `pro` (Antigravity silently drops files with unknown models).
- **Dry-run mode:** Pass `check: true` (for CI or previewing) to write nothing and report each file as `changed`, `unchanged`, or `skipped (<reason>)`.
- **Why OpenCode needs `sync`:** OpenCode cannot override an agent's model at dispatch time (`subagent` uses the model and reasoning effort in `.opencode/agents/<agent>.md`), so run `sync` after editing OpenCode model or effort settings in `.agents/team.json`.

## How vitruvian-core uses it

In `vitruvian-core`, `.agents/team.json` is generated from `.agents/roster/agents.tsv` by running `bazel run //tools/agent-roster -- --write`. Do not hand-edit `.agents/team.json` in this repository. A drift check (`bazel run //tools/agent-roster -- --check`) verifies that it matches the roster.

## Reference

### File location and limits

- **Path:** `.agents/team.json` at the repository root (optional). It may be a symlink, but its real target must be inside the repository; a link pointing outside reports `.agents/team.json must be inside the repository`, and a dangling link reports an error starting with `.agents/team.json is a dangling symlink`.
- **JSON format:** Must be a valid JSON object. Malformed JSON produces an error starting with `invalid JSON:`.
- **Size limit:** 64 KiB. When the file is larger than 64 KiB, it is not read and produces a size-limit error.
- **Unknown keys:** Any key not listed below is an error.

### Top-level keys

| Key | Type | Rule |
|---|---|---|
| `$schema` | `string` | Optional. Schema URL (`https://vitruviansoftware.dev/schemas/orchestrator-team.json`). |
| `engine` | `string` | Optional. Repo-wide default engine: `"native"` (default) or `"gemini"`. |
| `notes` | `string` | Optional. Repo-wide notes for every specialist. At most 2000 characters after display-text sanitization. |
| `tiers` | `object` | Optional. Per-tier defaults. Allowed keys: `lead`, `build`, `deep`, `light`. |
| `roles` | `object` | Optional. Per-role settings. Allowed keys: `lead`, `developer`, `infrastructure`, `build`, `operations`, `qa`, `security`, `product`, `docs`, `release`. |

### Tier keys (`tiers.<tier>`)

Each tier value is an object with any of these optional keys:

| Key | Type | Rule |
|---|---|---|
| `engine` | `string` | Optional. Per-tier engine: `"native"` or `"gemini"`. |
| `gemini` | `string` | Optional. Must match `^gemini-[a-z0-9.-]+$` and must not contain `-low`, `-lite`, or `flash-lo`. Resolves to `null` for the `lead` tier. |
| `claude-code` | `string` | Optional. Model for Claude Code. Must not contain `-low`, `-lite`, or `flash-lo`. |
| `antigravity` | `string` | Optional. Model for Antigravity. Must not contain `-low`, `-lite`, or `flash-lo`. |
| `opencode` | `string` | Optional. Model for OpenCode. Must not contain `-low`, `-lite`, or `flash-lo`. |
| `effort` | `string` | Optional. One of `"medium"`, `"high"`, `"xhigh"`, `"max"`. `"low"` is an error. |

### Role values (`roles.<role>`)

A role value is either the string `"off"` (not allowed for `lead`) or an object with any of these optional keys:

| Key | Type | Rule |
|---|---|---|
| `agent` | `string` | Optional. Agent name in your repository. Must match `^[a-z0-9][a-z0-9-]{0,63}$`. Defaults to the role ID. |
| `tier` | `string` | Optional. One of `"lead"`, `"build"`, `"deep"`, `"light"`. Defaults to the role's default tier. |
| `engine` | `string` | Optional. Per-role engine: `"native"` or `"gemini"`. |
| `gemini` | `string` | Optional. Per-role Gemini model override. Must match `^gemini-[a-z0-9.-]+$` and must not contain `-low`, `-lite`, or `flash-lo` (resolves to `null` for the `lead` tier). |
| `claude-code` | `string` | Optional. Per-role Claude Code model override. Same rules as `tiers.<tier>.claude-code`. |
| `antigravity` | `string` | Optional. Per-role Antigravity model override. Same rules as `tiers.<tier>.antigravity`. |
| `opencode` | `string` | Optional. Per-role OpenCode model override. Same rules as `tiers.<tier>.opencode`. |
| `effort` | `string` | Optional. Per-role effort override. One of `"medium"`, `"high"`, `"xhigh"`, `"max"`. `"low"` is an error. |
| `notes` | `string` | Optional. Role-specific notes prepended to the brief with top-level `notes`. At most 2000 characters after display-text sanitization. |

### `team` tool output

The `team` tool takes one optional input, `root` (the absolute repository path), and returns an object with these keys:

| Key | Type | Rule |
|---|---|---|
| `file` | `string \| null` | `".agents/team.json"` whenever the file is found (including when it has errors), or `null` only when absent. |
| `errors` | `string[]` | Parse (`invalid JSON: ...`), validation, symlink, size-limit, or file-read errors. Empty when valid or absent. |
| `notes` | `string` | Resolved top-level notes. |
| `roles` | `object[]` | Resolved entries for all ten roles in order (`role`, `agent`, `dispatch`, `source`, `tier`, `engine`, `gemini`, `model`, `effort`, `notes`). `source` is `"team"`, `"generic"`, or `"off"`; `"off"` sets `agent`, `dispatch`, and `engine` to `null`. |
