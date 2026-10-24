# Antigravity plugins

Plugins for the Antigravity desktop app that we share across the team. Each
one lives in its own folder under `plugins/` and is the folder Antigravity
loads, so installing one is a link into `~/.gemini/config/plugins/`.

| Plugin | What it does |
| --- | --- |
| [`ext-marketplace`](plugins/ext-marketplace/README.md) | Lists installed and active extensions, dynamically toggles enabled/disabled state, and provides a one-click marketplace catalog to install or update extensions. |
| [`gh-watch`](plugins/gh-watch/README.md) | Watches pull requests and wakes the owning conversation when CI starts failing. |
| [`hookify`](plugins/hookify/README.md) | Creates and evaluates zero-code markdown/regex guardrails and tool-argument rewrites on `PreToolUse` and `Stop`. |
| [`live-context`](plugins/live-context/README.md) | Injects live GitHub PR/issue/git state and anti-drift response contracts as `PreInvocation` ephemeral messages, and verifies response shape on `Stop`. |
| [`ralph-loop`](plugins/ralph-loop/README.md) | Runs self-referential iterative development loops via `Stop` hooks until completion promises are met or max iterations are reached. |
| [`receipts-report`](plugins/receipts-report/README.md) | Analyzes local `transcript.jsonl` files and git history to surface token/step waste hotspots and generate HTML/CSV engineering impact receipts. |
| [`savvy-fleet`](plugins/savvy-fleet/README.md) | Tiered orchestrator-worker delivery workflow (`savvy-flow`) with a live subagent fleet progress, cost, and trajectory telemetry panel. |
| [`security-guidance`](plugins/security-guidance/README.md) | Three-layer AppSec guard: instant pattern warnings on edits, turn-end diff review on `Stop`, and pre-commit vulnerability checks. |
| [`worktree-band`](plugins/worktree-band/README.md) | Tracks the active feature branch, pull request checks, and worktree/Bazel disk usage with safe one-click cleanup after merge. |

These are not native macOS apps, so the release contract in
[`apps/desktop/AGENTS.md`](../AGENTS.md) (DMGs, Homebrew cask, downloads
catalog) does not apply to them.
