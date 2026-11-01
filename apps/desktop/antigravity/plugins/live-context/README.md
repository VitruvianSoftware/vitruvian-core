# live-context

An Antigravity desktop plugin that gives the agent live Git and GitHub state
and checks the shape of its replies, through Antigravity's native
`PreInvocation` and `Stop` lifecycle hooks, paired with a live configuration
and diagnostics side panel.

## What it does

- **`PreInvocation` hook (`hooks/inject-live-context.sh`)**: Before each model
  invocation, injects a transient `ephemeralMessage` (`injectSteps: [{ ephemeralMessage }]`)
  carrying:
  - Current Git branch, HEAD commit, and dirty working-tree summary of the
    conversation's workspace, read with `git` on every turn
  - Open pull requests, recently merged pull requests, and open issue count
    from GitHub. The side panel's snapshot is used while it is under two
    minutes old; otherwise the hook asks `gh` itself (3 s limit) and refreshes
    the snapshot. If neither works, the message says the state is unknown,
    never that there are no PRs.
  - The user's active response contract (gist-first structure, surprise-first
    ordering, and no empty filler endings)
- **`Stop` hook (`hooks/verify-response-shape.sh`)**: When the agent finishes a
  turn (`terminationReason == "NO_TOOL_CALL"`), inspects the assistant's latest
  reply in `transcript.jsonl`. Checks whether the final non-code line ends with
  empty filler such as `"Nothing needed from you."` or `"No action needed."`:
  - In `log` mode (default), records the verdict in `~/.gemini/antigravity/live-context-state/verdicts.jsonl`
    and returns `{ "decision": "allow" }`.
  - In `enforce` mode, returns `{ "decision": "continue", "reason": "RESPONSE CONTRACT: ..." }`
    at most once per turn (`executionNum <= 1`) so the agent revises the ending
    without ever entering an infinite loop.
- **Side panel**: Lets you toggle live Git/GitHub injection, switch between
  `log` and `enforce` modes, customize the response contract rules, refresh the
  GitHub state snapshot immediately, and inspect recent `Stop` verdicts and
  OpenUI Lang v0.5 state.

## Requirements

The hooks are written in Rust using only the standard library. The first time
a hook runs, `hooks/rust-hook.sh` compiles it with `rustc` (about 1-2 s) into
`~/.cache/antigravity-plugins/`, and later runs reuse that binary. You need
Rust installed ([rustup.rs](https://rustup.rs)); without it the hook tells the
agent that live state is unknown, and says why on stderr. The side panel runs
on Antigravity's Node.js, and the live state needs `git` and an authenticated
`gh`.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/live-context
```

Or from a local checkout:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/live-context
```

Then enable it under Customizations → Installed, and open the panel from any
conversation: ⋮ menu → Extensions → Live Context.

## Update

Disable the plugin under Customizations → Installed, pull the latest changes,
and enable it again:

```bash
git -C ~/.gemini/config/plugins/live-context pull
```

## Layout

| Path | What it is |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `hooks.json` | `PreInvocation` and `Stop` lifecycle hook definitions |
| `hooks/inject-live-context.sh` | Emits `injectSteps: [{ ephemeralMessage }]` before model calls |
| `hooks/verify-response-shape.sh` | Validates response shape on `Stop` and logs verdicts |
| `hooks/rust-hook.sh` | Builds a hook from `hooks/src` with `rustc` on first use, then runs it |
| `hooks/src/` | The hooks: `lib.rs` (logic and tests), `json.rs`, `bin/*.rs` (entry points) |
| `rules/AGENTS.md` | Standing instructions for live state precedence and response contract |
| `skills/live-context/SKILL.md` | Skill for configuring live context injection and response shape rules |
| `sidecars/panel/sidecar.json` | Sidecar process and auxiliary pane UI manifest |
| `sidecars/panel/main.mjs` | Sidecar backend: refreshes Git/GitHub cache, serves `/api/state`, `/api/openui`, `/api/settings` |
| `sidecars/panel/lib/core.mjs` | Pure functions (`buildEphemeralContextPayload`, `checkResponseContract`, `formatLiveGitSummary`, `evaluateStopShape`) |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, HTML compiler, and `toOpenUILang(state)` |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive side panel |

## Test

From the plugin folder:

```bash
node --test sidecars/panel/lib/core.test.mjs sidecars/panel/lib/openui.test.mjs sidecars/panel/lib/version.test.mjs
rustc --edition 2021 --test hooks/src/lib.rs -o /tmp/live-context-hooks-test && /tmp/live-context-hooks-test
```

In the `vitruvian-core` monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/live-context/...
```
