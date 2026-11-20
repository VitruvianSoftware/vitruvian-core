---
status: completed
---

# Orchestrator generic team: role-named agents in the plugin

Step 2 of 5 (step 1, the team file, is
`docs/superpowers/specs/2026-11-19-orchestrator-team-file.md`, merged as #5223). After
this step the plugin copies ship a generic, role-named team that works in any repository,
and vitruvian-core keeps its named team (wren, scout, …) as project files, mapped through
its `.agents/team.json`.

## What changes

### Two profiles from one roster

`tools/agent-roster` renders two profiles:

| Profile | Agents | Written to |
|---|---|---|
| **project** (vitruvian-core) | named: beacon, wren, atlas, forge, ridge, scout, aegis, compass, quill, pace | `.claude/agents/`, `.agents/agents/`, `.opencode/agents/` (unchanged) |
| **generic** (plugin) | role-named: lead, developer, infrastructure, build, operations, qa, security, product, docs, release | `apps/claude-code/plugins/vitruvian-orchestrator/agents/`, `apps/antigravity/plugins/vitruvian-orchestrator/agents/`, and new `apps/opencode/plugins/vitruvian-orchestrator/agents/` |

The plugin no longer ships named agents. Project files are unchanged.

New sources:

- `.agents/roster/generic/roles.tsv`: `role`, `tier`, `description` for the ten roles.
  Descriptions say "in this repository", never vitruvian-core.
- `.agents/roster/generic/prompts/<role>.md`: one prompt body per role. It is generic:
  read the repository's `AGENTS.md` (or `CLAUDE.md`, `CONTRIBUTING.md`) first and follow
  it; use the project's own build, test and git commands; never assume a tool, path or
  agent name.
- `.agents/roster/team-notes.md`: vitruvian-core's repo-wide notes. The generator puts this
  text in the top-level `notes` of our `.agents/team.json`: Bazel targets for every git,
  build, test and GitHub operation; act under your own GitHub App identity; never run
  `speaker-broadcast` or other announcement commands from a delegated run.

Tiers come from `tiers.tsv` for both profiles (unchanged).

### One generic lead skill

`.agents/roster/skills/orchestrate/{claude-code,antigravity,opencode}.md` become generic,
because Claude Code and Antigravity load only the plugin's skill, so the same text runs in
vitruvian-core. They must contain no vitruvian-core names, Bazel targets, paths or named
agents:

- The roster table becomes a role table: `| Role | Tier | Model | What it does |` from
  `generic/roles.tsv` and `tiers.tsv`.
- Routing is by role through the `team` tool (step 1): dispatch the row's `dispatch` id.
- The staffing table (implementer, QA, docs, security review, UAT) names roles, not agents:
  `qa` for QA, `security` for security review, `product` for UAT, `docs` for docs, the
  domain role for implementation.
- Build, test and git commands: "the ones the repository's own instructions name", not
  `bazel …`.
- Repo-specific rules come from the team notes and the repository's `AGENTS.md`.

The generated copies: the two plugin `SKILL.md` files (as now), plus new
`apps/opencode/plugins/vitruvian-orchestrator/skills/orchestrate/SKILL.md`. The project
`.opencode/skills/orchestrate/SKILL.md` is rendered from the same generic source.

### Driver template

The driver body (`lib.rs` ~936-1041) loses its vitruvian-core specifics for the generic
profile:

- Worktree: "create it the way the repository's instructions say; if they say nothing,
  `git worktree add`". The project profile keeps `bazel run //tools/worktree`.
- "`AGENTS.md` binds Gemini … Bazel targets" becomes "the repository's own instructions
  (AGENTS.md, CLAUDE.md, CONTRIBUTING.md) bind Gemini".
- Announcement rule: generic wording, "never run notification or announcement commands";
  the project profile keeps the explicit `speaker-broadcast` name.
- `agy-delegate` stays (Gemini-optional drivers are step 4).

### Dispatch id (shared core and the `team` tool)

`resolveTeam` rows gain `dispatch`, the id the harness needs to start that agent:

- `source: "team"`: `dispatch` = `agent`.
- `source: "generic"`: Claude Code `vitruvian-orchestrator:<role>` (plugin agents are
  namespaced); Antigravity and OpenCode `<role>`.
- `source: "off"`: `dispatch: null`.

### Drift test

A test fails if any generic plugin output (the three plugins' `agents/*.md` and
`skills/orchestrate/SKILL.md`) contains `vitruvian-core`, `bazel`, `//tools`,
`speaker-broadcast`, `James`, or any project agent name (beacon, wren, atlas, forge, ridge,
scout, aegis, compass, quill, pace) as a whole word. Existing drift tests that expect named
plugin agents are updated to expect role-named ones.

## Out of scope

- OpenCode loading the generic agents outside this repository: the files are generated in
  the plugin folder; registering them with OpenCode is part of publishing (step 5).
- Drivers that work without Gemini (step 4), `init`/`sync` (step 3).
