# Flights

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/flights`.

## Interface
- `[controller.js:createController]`
- `[enrichment.js:createEnrichment]`
- `[evidence.js:createEvidence]`
- `[index.js:createCivilFlightLayer]`
- `[ingestion.js:createIngestion]`
- `[ingestion.js:createFlightFeed]`
- `[lifecycle.js:createLifecycle]`
- `[modelSpec.js:civilAircraftModelSpec]`
- `[motion.js:createMotion]`
- `[policy.js:FOCUS_EVIDENCE_DEV]`
- `[policy.js:MIL_TINT]`
- `[policy.js:EMERGENCY_TINT]`
- `[policy.js:GROUND_SCALE]`
- `[policy.js:PLANE_MODEL_URL]`
- `[policy.js:MODEL_ALT_CEIL_M]`
- `[policy.js:MODEL_MIN_PX]`
- `[policy.js:TRACKED_MODEL_MIN_PX]`
- `[policy.js:TRACKED_MODEL_MAX_PX]`
- `[policy.js:MODEL_NATIVE_RADIUS_M]`
- `[policy.js:MODEL_SCALE]`

## Invariants
- [hiddenContactRotation.test.mjs:24]: `import assert from 'node:assert/strict';`
- [hiddenContactRotation.test.mjs:44]: `assert.ok(HIDDEN_CONTACT_DR_TICKS > 1);`
- [hiddenContactRotation.test.mjs:45]: `assert.ok(`
- [ingestion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ingestion.test.mjs:61]: `assert.equal(probe.feed._activeUpdateControllers.size, 1);`
- [ingestion.test.mjs:65]: `await assert.rejects(request, { name: 'AbortError' });`
- [motion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [motion.test.mjs:58]: `assert.ok(Cesium.Cartesian3.distance(actual, expected) < 1e-8);`
- [motion.test.mjs:79]: `assert.equal(spy.mock.callCount(), 1);`
- [ownership.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [enrichment.js:42]: `function _enqueueEnrich(key, query, onData, priority = false) {`
- [enrichment.js:46]: `const job = { query, onData };`
- [enrichment.js:82]: `return flightState.feed._source.getEnrichment?.(job.query, {`
- [ingestion.js:97]: `console.warn('[Data:Flights] Fetch error:', e);`
- [ingestion.test.mjs:74]: `async getSnapshot(query) {`
- [ingestion.test.mjs:75]: `assert.equal(query.latitude, 39);`
- [ownership.test.mjs:107]: `getEnrichment(query, options) {`
- [policy.js:392]: `*  floor cache — no fetch, no `sampleHeight`, nothing async — so it cannot`
- [queries.js:147]: `// feeds query/analyst/subject APIs — `findByQuery` (voice track-by-name),`
- [queries.js:245]: `* record (analyst query engine seam). Pure — no Cesium types, no fetches;`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/flights/...`
