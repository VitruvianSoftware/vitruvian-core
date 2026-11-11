# Transit

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/transit`.

## Interface
- `[controls.js:createControls]`
- `[height.js:createHeight]`
- `[index.js:createTransitLayer]`
- `[ingestion.js:FUTURE_STAMP_TOLERANCE_MS]`
- `[ingestion.js:ORDER_REJECTS_BEFORE_RESET]`
- `[ingestion.js:createIngestion]`
- `[lifecycle.js:createLifecycle]`
- `[movement.js:fixDistanceM]`
- `[movement.js:displacementPlausible]`
- `[movement.js:initializePlayback]`
- `[movement.js:recordFix]`
- `[movement.js:updatePlayback]`
- `[movement.js:syncPlayback]`
- `[movement.js:playbackPosition]`
- `[movement.js:attachFloorToPlace]`
- `[movement.js:applyDisplayCourse]`
- `[movement.js:displayMotion]`
- `[policy.js:TRANSIT_SELECTED_OVERLAY_SOURCE_ID]`
- `[policy.js:TRANSIT_SELECTED_OVERLAY_SOURCE_OPTIONS]`
- `[policy.js:TRANSIT_POLL_MS]`

## Invariants
- [lifecycle.test.mjs:24]: `import assert from 'node:assert/strict';`
- [lifecycle.test.mjs:444]: `assert.equal(entry.to.lat, 42.36);`
- [lifecycle.test.mjs:445]: `assert.equal(`
- [movement.test.mjs:24]: `import assert from 'node:assert/strict';`
- [movement.test.mjs:42]: `assert.equal(displacementPlausible('bus', 583, 15), false);`
- [movement.test.mjs:43]: `assert.equal(displacementPlausible('bus', 583, 15, true), true);`
- [qaMetrics.js:290]: `* White-hot, Ironbow and noir require 0.85; black-hot keeps the inverse.`
- [qaMetrics.test.mjs:24]: `import assert from 'node:assert/strict';`
- [qaMetrics.test.mjs:50]: `assert.equal(reduceMotion(rows()).pass, true);`
- [qaMetrics.test.mjs:51]: `assert.equal(reduceMotion(rows().map((r) => ({ ...r, x: 0 }))).pass, false);`

## Side Effects
- [ingestion.js:51]: `* How far ahead of the snapshot's own fetch time a vehicle stamp may sit`
- [ingestion.js:54]: `* froze for as long as the clock stayed wrong. Beyond this the fetch time is`
- [ingestion.js:183]: `// fetch time, and that is the only honest clock for "how old are these`
- [lifecycle.test.mjs:206]: `const originalFetch = globalThis.fetch;`
- [lifecycle.test.mjs:269]: `globalThis.fetch = async (url) => {`
- [lifecycle.test.mjs:337]: `globalThis.fetch = originalFetch;`
- [policy.js:252]: `* the age helper: the vehicle's own stamp, else the snapshot's fetch time.`
- [policy.js:255]: `* @param {number|null} [fetchedAtMs] Snapshot fetch time.`
- [policy.js:269]: `* feed header's, else fetch time) and says which it used. A record that somehow`
- [queries.js:231]: `* query engine. On demand only (once per spoken query); [] while the`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/transit/...`
