# receipts-report

An Antigravity desktop plugin that turns raw conversation trajectories into
structured engineering impact receipts. It scans `.system_generated/logs/transcript.jsonl`
across `~/.gemini/antigravity/brain`, correlates agent turns with project
commits and pull requests, flags context-truncation and error hotspots, and
exports standalone HTML or CSV reports.

## What it does

- A `PostInvocation` hook (`hooks/record-turn.sh`) records lightweight session
  metadata (`conversationId`, `workspacePaths`, `modelName`, `invocationNum`,
  and step count) into `~/.gemini/antigravity/receipts-report-inbox/` after
  each agent turn without blocking or altering execution.
- The background sidecar ingests those turn notes and scans session transcripts
  under `~/.gemini/antigravity/brain/<conversation-id>/.system_generated/logs/transcript.jsonl`,
  counting user prompts (`USER_INPUT`), planner responses (`PLANNER_RESPONSE`),
  tool invocations (`tool_calls`), subagent dispatches (`invoke_subagent`),
  step errors (`status == "ERROR"`), and truncated fields (`truncated_fields`).
- Sessions are grouped by workspace/project and correlated with git commits and
  pull requests created during the window so you can see not just how many
  steps ran, but what shipped per project.
- An anomaly detector (`detectTokenHotspots`) flags sessions with heavy field
  truncation, high tool-error rates, or runaway tool loops.
- The side panel renders live project summaries, hotspot alerts, and an OpenUI
  Lang v0.5 dashboard, with one-click export to standalone HTML or CSV.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/receipts-report
```

Or from a local checkout:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/receipts-report
```

Then enable it under Customizations → Installed, and open the panel from any
conversation: ⋮ menu → Extensions → Receipts Report.

## Update

Disable the plugin under Customizations → Installed, pull the latest changes,
and enable it again:

```bash
git -C ~/.gemini/config/plugins/receipts-report pull
```

## Layout

| Path | What it is |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `hooks.json`, `hooks/record-turn.sh` | `PostInvocation` hook that records session turn metadata |
| `rules/AGENTS.md` | Standing rule teaching agents how to query and export session receipts |
| `skills/receipts-report/SKILL.md` | On-demand skill for generating HTML/CSV impact reports |
| `sidecars/panel/sidecar.json` | Sidecar process and auxiliary pane UI manifest |
| `sidecars/panel/main.mjs` | Sidecar backend: scans transcripts, serves `/api/state`, `/api/openui`, `/api/export` |
| `sidecars/panel/lib/core.mjs` | Pure transcript parser, project aggregator, hotspot detector, and CSV/HTML formatters |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, HTML compiler, and `toOpenUILang(state)` |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive side panel |

## Test

From the plugin folder:

```bash
node --test sidecars/panel/lib/core.test.mjs sidecars/panel/lib/openui.test.mjs sidecars/panel/lib/version.test.mjs
```

In the `vitruvian-core` monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/receipts-report/...
```
