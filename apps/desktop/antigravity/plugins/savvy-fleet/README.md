# savvy-fleet

An Antigravity desktop plugin that ports the tiered orchestrator-worker workflow (`savvy-flow`) and live subagent fleet progress monitor (`savvy-progress`) to Antigravity.

## Features

- **Tiered Orchestrator-Worker Flow (`savvy-flow`)**: Structured 5-phase engineering workflow (`plan` → `design` → `delegate` → `review` → `close`) with 5 complexity tiers (`fable`, `heavy`, `careful`, `medium`, `light`) mapped to Vitruvian specialist subagents (`beacon`, `wren`, `atlas`, `ridge`, `scout`, `aegis`, `quill`, `compass`, `pace`).
- **Automatic Subagent Discovery**: Combines real-time `PostToolUse` hook notifications on `invoke_subagent` and `send_message` with live parsing of Antigravity's `transcript.jsonl` to track every spawned subagent, its role, tier, round, tool executions, and completion status.
- **Cost & Token Estimation**: Estimates token usage and USD run cost across model families (`fable`, `opus-5-5`, `opus`, `sonnet`, `haiku`, `gemini-pro`, `gemini-flash`) with context window utilization tracking.
- **OpenUI Lang v0.5 Dashboard**: Exposes `/api/state` and `/api/openui` producing a valid `Card([Header(...), Grid(4, [...]), Table([...])])` specification rendered live in the auxiliary sidecar panel.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/savvy-fleet
```

Or link directly from the `vitruvian-core` monorepo:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/savvy-fleet
```

Then enable it under Customizations → Installed, or open the sidecar panel from any conversation via `[Savvy Fleet](sidecar://savvy-fleet/panel/)`.

## Update

```bash
git -C ~/.gemini/config/plugins/savvy-fleet pull
```

Disable and re-enable the plugin after updating so Antigravity restarts the background sidecar process.

## Requirements

The hook is written in Rust using only the standard library. The first time
it runs, `hooks/rust-hook.sh` compiles it with `rustc` (about 1 s) into
`~/.cache/antigravity-plugins/`, and later runs reuse that binary. You need
Rust installed ([rustup.rs](https://rustup.rs)); without it the hook does
nothing but say why on stderr. The side panel runs on Antigravity's
Node.js.

## Architecture

| Path | Purpose |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `hooks.json`, `hooks/track-subagent.sh` | `PostToolUse` hook capturing `invoke_subagent` and `send_message` events into `~/.gemini/antigravity/savvy-fleet-inbox/` |
| `hooks/rust-hook.sh` | Builds the hook from `hooks/src` with `rustc` on first use, then runs it |
| `hooks/src/` | The hook: `lib.rs` (logic and tests), `main.rs` (entry point) |
| `rules/AGENTS.md` | Standing instructions for reporting flow progress and opening the Savvy Fleet panel |
| `skills/savvy-flow/SKILL.md` | Complete `savvy-flow` tiered orchestration guide for Antigravity subagents |
| `skills/savvy-fleet/SKILL.md` | Skill entrypoint for inspecting fleet status and managing flows |
| `sidecars/panel/sidecar.json` | Sidecar manifest (`SIDECAR_UI_ENTRYPOINT_AUX_PANE`) |
| `sidecars/panel/main.mjs` | Sidecar HTTP server (`/api/state`, `/api/openui`, `/api/progress`, `/api/step`, `/api/reset`) |
| `sidecars/panel/lib/core.mjs` | Pure functions: `PHASES`, `TIERS`, `mergeFlowProgress`, `extractSubagentsFromTranscript`, `estimateRunCost`, `summariseFleetState` |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, HTML compiler, and `toOpenUILang(state)` |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive sidecar web panel |

## Test

Run the panel's unit tests with Node's built-in test runner, and the hook's
with `rustc --test`:

```bash
node --test sidecars/panel/lib/core.test.mjs sidecars/panel/lib/openui.test.mjs sidecars/panel/lib/version.test.mjs
rustc --edition 2021 --test hooks/src/lib.rs -o /tmp/savvy-fleet-hook-test && /tmp/savvy-fleet-hook-test
```

Or via Bazel in the monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/savvy-fleet/...
```
