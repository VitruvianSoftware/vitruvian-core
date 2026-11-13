---
name: live-context
description: Configure live Git/GitHub PreInvocation context injection, customize the response contract rules, switch Stop hook verification between log and enforce modes, and inspect recent response shape verdicts.
---

# Live Context Skill

Use this skill when the user wants to inspect or adjust live context injection
(`hooks/inject-live-context.sh`) or response shape verification
(`hooks/verify-response-shape.sh`).

## Workflow

1. **Inspect state**: Read `~/.gemini/antigravity/live-context-state/settings.json`,
   `snapshot.json`, and `verdicts.jsonl` (or query the Live Context sidecar's
   `/api/state` route).
2. **Adjust mode or toggles (`settings.json`)**:
   - `injectGit` (`true`/`false`, default `true`): Include live workspace branch and dirty count.
   - `injectGitHub` (`true`/`false`, default `true`): Include open PRs, recently merged PRs, and open issue count.
   - `injectContract` (`true`/`false`, default `true`): Include the response contract in every `PreInvocation` `ephemeralMessage`.
   - `mode` (`"log"` or `"enforce"`, default `"log"`): Controls whether `Stop` hook violations only log to `verdicts.jsonl` or return `{"decision": "continue"}` once per turn to prompt a revision.
   - `repo` (`"owner/repo"`, default `""`): GitHub repository slug passed to `gh --repo`. When unset or empty, the hook derives it automatically from the workspace's git `origin` remote URL rather than a hard-coded repository.
   - `minChars` (number, default `300` in hooks; side panel clamps to `>= 50`): Minimum assistant reply length before `Stop` response-shape checks apply.
   - `contractText` (string, default built-in `DEFAULT_RESPONSE_CONTRACT`): Custom response contract text injected on `PreInvocation`.
