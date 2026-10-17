# agent-app test fixtures

Responses GitHub gives to the exact queries `agent-app.sh` sends. The test's
fake `gh` passes them through the script's own `--jq` filters with a real
`jq`, so a typo in a filter fails the test.

Captured from GitHub on 2026-10-16 with `gh api graphql`:

| File | PR | Shape |
|---|---|---|
| `pr-view-id.json` | #3425 | `gh pr view --json id` |
| `hold-open.json`, `enqueue-open.json` | #3350 | open, nothing armed |
| `hold-queued.json`, `enqueue-queued.json` | #3425 | in the merge queue |
| `hold-merged.json`, `enqueue-merged.json` | #3427 | merged |

No PR had auto-merge armed or `do-not-automerge` on at the time, so these are
made from the captured ones with `jq`, changing only the fields named:

| File | From | Changed |
|---|---|---|
| `hold-armed.json` | `hold-open.json` | `autoMergeRequest` set, `agent-fast-lane` label |
| `hold-held.json` | `hold-open.json` | labels `agent-fast-lane`, `do-not-automerge` |
| `hold-armed-labelled.json` | `hold-armed.json` | `do-not-automerge` added |
| `hold-queued-labelled.json` | `hold-queued.json` | `do-not-automerge` label |
| `hold-gate-dev-deploy-red.json` | `hold-open.json` | labels `autorelease: pending`, `dev-deploy-red` |
| `hold-gate-beta-not-built.json` | `hold-open.json` | labels `autorelease: pending`, `beta-not-built` |
| `enqueue-armed.json` | `enqueue-open.json` | `autoMergeRequest` armed by wren, squash |
