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
  `Path` and `Content` also read Antigravity's own file tools: `TargetFile`,
  `AbsolutePath`, `CodeContent`, `ReplacementContent` and each
  `ReplacementChunks` entry. Patterns are JavaScript regular expressions
  (lookaround, lazy quantifiers, named groups and backreferences included).
- **Permission Gating & Argument Rewriting (`PreToolUse`):**
  - `allow` — permit matching calls immediately
  - `warn` / `ask` — prompt the user with your custom Markdown explanation
  - `force_ask` — require interactive confirmation even in auto-approve sessions
  - `block` / `deny` — block the tool call and return remediation guidance to the agent
  - `overwrite` — rewrite tool arguments on the fly before execution (sent to
    Antigravity as `overwrite`, and as `updatedInput` for other hosts)
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

## Requirements

The hook is written in Rust using only the standard library. The first time
it runs, `hooks/rust-hook.sh` compiles it with `rustc` (about 1-2 s) into
`~/.cache/antigravity-plugins/`, and later runs reuse that binary. You need
Rust installed ([rustup.rs](https://rustup.rs)). Without it, the hook asks
before every tool call and says its rules are not being enforced; stderr says
why. The side panel runs on Antigravity's Node.js.

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
| `hooks/rust-hook.sh` | Builds the hook from `hooks/src` with `rustc` on first use, then runs it |
| `hooks/src/` | The hook: `lib.rs` (rules, decisions, tests), `regex.rs` (JavaScript regular expressions), `json.rs`, `main.rs` |
| `rules/AGENTS.md` | Standing instructions for agents working with Hookify |
| `skills/hookify/SKILL.md` | Skill for authoring and testing Hookify rules |
| `sidecars/panel/sidecar.json` | Sidecar manifest |
| `sidecars/panel/main.mjs` | Sidecar backend and REST API |
| `sidecars/panel/lib/core.mjs` | The panel's rule parser and evaluator (its test bench); the hook's is `hooks/src/lib.rs` |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, renderer, and state serializer |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive rule manager and test bench |

## Test

From the plugin folder:

```bash
node --test sidecars/panel/lib/
rustc --edition 2021 --test hooks/src/lib.rs -o /tmp/hookify-hook-test && /tmp/hookify-hook-test
```

Or through Bazel in the monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/hookify/...
```
