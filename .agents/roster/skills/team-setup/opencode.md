---
name: team-setup
description: Set up a starter orchestrator team file or sync its model settings into your repository's agent files in OpenCode.
---

# Team Setup (OpenCode)

Set up or sync `.agents/team.json` for this repository.

## 1. Ask which action

If the user did not choose an action yet, explain both options in one line each and ask which to run:

- **`init`**: Writes a starter `.agents/team.json` (and optionally copies editable `team-<role>` starter agents for chosen roles into `.opencode/agents/`). Never overwrites existing files.
- **`sync`**: Copies explicit model and effort settings from `.agents/team.json` into the repository's own agent files (Claude Code, Antigravity, and OpenCode).

## 2. Run the `team_setup` tool

Call the `team_setup` tool with `root` set to the absolute path of the repository:

- For **`init`**: pass `action: "init"`. Include `agents: ["<role>", ...]` (any role except `lead`) only if the user asked for editable `team-<role>` starter agents.
- For **`sync`**: offer to run with `action: "sync"` and `check: true` first to preview changes without writing. Run with `check: false` (or omitted) once the user wants to apply them.

## 3. Show the report

Print the per-file result as a short list (`created`, `changed`, `unchanged`, or `skipped` with its reason).

After **`init`**, tell the user to edit `.agents/team.json` (each role takes `agent`, `tier`, `engine`, per-harness models and `effort`; the `$schema` line at the top lets an editor check it) and run `sync` when ready to apply model changes to agent files.
