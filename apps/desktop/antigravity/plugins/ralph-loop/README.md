# ralph-loop

An Antigravity desktop plugin that implements the Ralph Wiggum iterative
development loop technique: an agent conversation continues iterating on a task
across turns until it genuinely satisfies the completion criteria and emits
`<promise>...</promise>`, or hits a maximum iteration bound.

## What it does

- **Stop-hook continuation (`hooks/ralph-stop.sh`)**: Intercepts turn completion
  for conversations with an active loop in
  `~/.gemini/antigravity/ralph-loop-state/<conversationId>.json`. When
  `iteration < maxIterations` and the last assistant message does not contain
  `<promise>${completionPromise}</promise>`, it increments `iteration` and
  returns `{"decision": "continue", "reason": "..."}`.
- **Interactive sidecar panel**: Start, inspect, wake, or cancel iterative loops
  for any conversation, configure `prompt`, `completionPromise`, and
  `maxIterations`, and monitor progress in real time.
- **Escape hatches**: Loops automatically stop when the completion promise is
  matched, when `maxIterations` is reached, or when cancelled from the side
  panel (`/api/cancel-loop`).
- **OpenUI Lang v0.5 dashboard**: Exposes `/api/openui` and renders an OpenUI
  Lang v0.5 summary card with KPIs and a loop status table.

## Requirements

The hook is written in Rust using only the standard library. The first time it
runs, `hooks/rust-hook.sh` compiles it with `rustc` (about a second) into
`~/.cache/antigravity-plugins/`, and later runs reuse that binary. You need
Rust installed ([rustup.rs](https://rustup.rs)). Without it the Stop hook lets every turn end (so an active loop does not continue) and says why on stderr. The side panel runs on
Antigravity's Node.js.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/ralph-loop
```

Or from a local checkout:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/ralph-loop
```

Then enable it under Customizations → Installed, and open it from any
conversation: the ⋮ menu → Extensions → Ralph Loop.

## Update

Disable the plugin under Customizations → Installed, pull the latest changes,
then enable it again:

```bash
git -C ~/.gemini/config/plugins/ralph-loop pull
```

## Layout

| Path | What it is |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `sidecars/panel/sidecar.json` | Background process and panel manifest |
| `sidecars/panel/main.mjs` | Panel backend: HTTP routes (`/api/state`, `/api/openui`, `/api/start-loop`, `/api/cancel-loop`, `/api/wake-loop`) |
| `hooks.json`, `hooks/ralph-stop.sh` | `Stop` hook that evaluates completion promises and continues active loops |
| `hooks/rust-hook.sh` | Builds the hook from `hooks/src` with `rustc` on first use, then runs it |
| `hooks/src/` | The hook: `lib.rs` (logic and tests), `json.rs`, `main.rs` (entry point) |
| `rules/AGENTS.md` | Standing instructions for agents operating inside a Ralph Loop |
| `skills/ralph-loop/SKILL.md` | Skill guide for starting, managing, and completing a Ralph Loop |
| `sidecars/panel/lib/core.mjs` | Panel logic: `createLoopState`, `updateLoopIteration`, `summariseLoops` |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, HTML compiler, and `toOpenUILang(state)` |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive side panel UI |

## Test

From the plugin folder:

```bash
node --test sidecars/panel/lib/*.test.mjs
rustc --edition 2021 --test hooks/src/lib.rs -o /tmp/ralph-loop-hook-test && /tmp/ralph-loop-hook-test
```

Or via Bazel in the monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/ralph-loop/...
```
