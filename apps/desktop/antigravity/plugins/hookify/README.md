# hookify

An Antigravity desktop plugin that brings declarative, zero-code guardrails to
`PreToolUse` and `Stop` hooks. Rules can be checked into a repository under
`.agents/hookify.*.md` or managed globally in
`~/.gemini/antigravity/hookify-rules.json` via the interactive Hookify side
panel.

## Features

- **Declarative Markdown & JSON Rules:** Define rules in `.agents/hookify.<name>.md`
  with YAML frontmatter and a Markdown message body, or store global rules in
  `~/.gemini/antigravity/hookify-rules.json`.
- **Rich Condition Operators:** Match tool arguments (`CommandLine`, `Path`,
  `Content`, `Replacement`, `Target`, or any nested field) using `regex_match`,
  `contains`, `not_contains`, `equals`, `starts_with`, and `ends_with`.
- **Permission Gating & Argument Rewriting (`PreToolUse`):**
  - `allow` — permit matching calls immediately
  - `warn` / `ask` — prompt the user with your custom Markdown explanation
  - `force_ask` — require interactive confirmation even in auto-approve sessions
  - `block` / `deny` — block the tool call and return remediation guidance to the agent
  - `overwrite` — rewrite tool arguments (`updatedInput`) on the fly before execution
- **Completion Assertions (`Stop`):** Block premature session completion (`continue: false`)
  when required conditions or transcript checks are not yet satisfied.
- **Interactive Sidecar Panel & OpenUI Lang v0.5:** Create, toggle, delete, and
  dry-run test rules against sample tool payloads, inspect recent hook trigger
  events, and export live telemetry as OpenUI Lang v0.5 (`GET /api/openui`).

## Rule Format (`.agents/hookify.<name>.md`)

```markdown
---
name: block-rm-rf
enabled: true
event: bash
action: block
conditions:
  - field: CommandLine
    operator: regex_match
    pattern: "rm\\s+-rf\\s+(/|~|\\$HOME)"
---
Refusing destructive `rm -rf` targeting root or home directory. Scope the path to a workspace subdirectory instead.
```

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/hookify
```

Or link a local checkout into Antigravity's plugin folder:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/hookify
```

Then enable it under Customizations → Installed, and open the side panel from
any conversation via the ⋮ menu → Extensions → Hookify.

## Update

Disable the plugin under Customizations → Installed, pull the latest changes,
and re-enable:

```bash
git -C ~/.gemini/config/plugins/hookify pull
```

## Layout

| Path | Description |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `hooks.json`, `hooks/evaluate-rules.sh` | `PreToolUse` and `Stop` hook entrypoint |
| `rules/AGENTS.md` | Standing instructions for agents working with Hookify |
| `skills/hookify/SKILL.md` | Skill for authoring and testing Hookify rules |
| `sidecars/panel/sidecar.json` | Sidecar manifest |
| `sidecars/panel/main.mjs` | Sidecar backend and REST API |
| `sidecars/panel/lib/core.mjs` | Pure rule parser, condition evaluator, and hook decision engine |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, renderer, and state serializer |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive rule manager and test bench |

## Test

From the plugin folder:

```bash
node --test sidecars/panel/lib/
```

Or through Bazel in the monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/hookify/...
```
