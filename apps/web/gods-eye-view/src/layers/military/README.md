# Military

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/military`.

## Interface
- `[controller.js:createController]`
- `[index.js:createMilitaryFlightLayer]`
- `[ingestion.js:createIngestion]`
- `[ingestion.js:createMilitaryFeed]`
- `[lifecycle.js:createLifecycle]`
- `[motion.js:createMotion]`
- `[policy.js:BILLBOARD_SCALE]`
- `[policy.js:MIL_ICON_COLOR]`
- `[policy.js:TRACKED_ICON_COLOR]`
- `[policy.js:EMERGENCY_ICON_COLOR]`
- `[policy.js:GROUND_SCALE]`
- `[policy.js:JET_MODEL_URL]`
- `[policy.js:MODEL_ALT_CEIL_M]`
- `[policy.js:MODEL_MIN_PX]`
- `[policy.js:TRACKED_MODEL_MIN_PX]`
- `[policy.js:TRACKED_MODEL_MAX_PX]`
- `[policy.js:MODEL_NATIVE_RADIUS_M]`
- `[policy.js:MODEL_SCALE]`
- `[policy.js:MODEL_MAX]`
- `[policy.js:MODEL_MAX_ALL]`

## Invariants
- [ingestion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ingestion.test.mjs:52]: `assert.equal(probe.feed._activeUpdateControllers.size, 1);`
- [ingestion.test.mjs:56]: `await assert.rejects(request, { name: 'AbortError' });`
- [ownership.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ownership.test.mjs:87]: `assert.equal(first.getParams().models3dMode, 'all');`
- [ownership.test.mjs:88]: `assert.equal(second.getParams().models3dMode, 'proximity');`
- [records.test.mjs:24]: `import assert from 'node:assert/strict';`
- [records.test.mjs:59]: `assert.equal(first.meta.altitudeFt, 1000 / 0.3048);`
- [records.test.mjs:60]: `assert.equal(first.meta.renderAltitudeM, 1040);`

## Side Effects
- [ingestion.js:88]: `console.warn('[Data:Military] Fetch error:', e);`
- [ownership.test.mjs:243]: `// About a third of a live adsb.lol /v2/mil fetch is contacts without a`
- [queries.js:183]: `* analyst record (analyst query engine seam) — same shape as the flights`
- [queries.js:373]: `* @param {object} [options] Query membership options.`
- [snapshotRenderer.js:56]: `// batch-resolved once after it. Never a fetch inside the loop.`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/military/...`
