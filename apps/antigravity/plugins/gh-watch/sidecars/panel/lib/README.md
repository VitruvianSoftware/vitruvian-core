# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/gh-watch/sidecars/panel/lib`.

## Interface
- `[actions.mjs:reviewAction]`
- `[decide.mjs:DEFAULT_HOLD_MS]`
- `[decide.mjs:bucketOf]`
- `[decide.mjs:normaliseChecks]`
- `[decide.mjs:countChecks]`
- `[decide.mjs:emptyState]`
- `[decide.mjs:decide]`
- `[decide.mjs:failingLines]`
- `[decide.mjs:wakeMessage]`
- `[flakes.mjs:FLAKE_WINDOW_MS]`
- `[flakes.mjs:FLAKE_THRESHOLD]`
- `[flakes.mjs:spotFlakes]`
- `[flakes.mjs:recordFlakes]`
- `[flakes.mjs:flakeCount]`
- `[flakes.mjs:tagFlaky]`
- `[flakes.mjs:listFlaky]`
- `[github.mjs:parsePrUrl]`
- `[github.mjs:fetchPr]`
- `[github.mjs:resolvePr]`
- `[github.mjs:setAutoMerge]`

## Invariants
- [actions.test.mjs:23]: `import assert from "node:assert/strict";`
- [actions.test.mjs:57]: `assert.deepEqual(await reviewAction({ repo: "o/r", number: 5 }, gh), {`
- [actions.test.mjs:61]: `assert.deepEqual(gh.calls, [`
- [decide.test.mjs:23]: `import assert from "node:assert/strict";`
- [decide.test.mjs:48]: `assert.equal(bucketOf(run("a", "IN_PROGRESS", null)), "pending");`
- [decide.test.mjs:49]: `assert.equal(bucketOf(run("a", "COMPLETED", "SUCCESS")), "pass");`
- [flakes.test.mjs:23]: `import assert from "node:assert/strict";`
- [flakes.test.mjs:42]: `assert.deepEqual(first.flaked, []);`
- [flakes.test.mjs:47]: `assert.deepEqual(rerun.flaked, []);`
- [landing.test.mjs:23]: `import assert from "node:assert/strict";`

## Side Effects
- [actions.test.mjs:209]: `throw new Error("HTTP 502");`
- [actions.test.mjs:213]: `/HTTP 502/,`
- [github.mjs:68]: `const match = PR_URL.exec(url ?? "");`
- [github.mjs:178]: `query($owner: String!, $name: String!, $number: Int!) {`
- [github.mjs:202]: ``query=${FEEDBACK_QUERY}`,`
- [inbox.mjs:111]: `const cd = CD.exec(part);`
- [inbox.mjs:118]: `const signUp = SIGN_UP.exec(part);`
- [inbox.mjs:146]: `const match = PR_URL.exec(text ?? "");`
- [logs.mjs:31]: `const match = RUN_URL.exec(url ?? "");`
- [notices.mjs:168]: ``Fetch \`${pr.base}\` from the remote and merge it into \`${pr.branch}\`. Do ...`

## Verification
- Run: `bazel test //apps/antigravity/plugins/gh-watch/sidecars/panel/lib/...`
