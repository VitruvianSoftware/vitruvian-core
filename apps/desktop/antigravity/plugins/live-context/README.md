# live-context

An Antigravity desktop plugin that ports `.claude/gh-live-state.sh` and
`~/.claude/response-contract-stop.py` to Antigravity's native `PreInvocation`
and `Stop` lifecycle hooks, paired with a live configuration and diagnostics
side panel.

## What it does

- **`PreInvocation` hook (`hooks/inject-live-context.sh`)**: Before each model
  invocation, injects a transient `ephemeralMessage` (`injectSteps: [{ ephemeralMessage }]`)
  carrying:
  - Current Git branch, HEAD commit, and dirty working-tree summary
  - Cached open pull requests, recently merged pull requests, and open issue
    count from GitHub (kept fresh by the background sidecar so the hook never
    blocks on slow network calls)
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
```

In the `vitruvian-core` monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/live-context/...
```
