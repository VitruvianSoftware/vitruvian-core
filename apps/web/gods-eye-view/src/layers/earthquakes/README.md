# Earthquakes

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/earthquakes`.

## Interface
- `[index.js:createEarthquakesLayer]`
- `[model.js:EARTHQUAKE_OVERLAY_SOURCE_ID]`
- `[model.js:EARTHQUAKE_OVERLAY_COHORT_LIMIT]`
- `[model.js:EARTHQUAKE_OVERLAY_COLLISION_CAPACITY]`
- `[model.js:depthColor]`
- `[model.js:createEarthquakeOverlayEntry]`
- `[model.js:selectEarthquakeOverlayCohort]`
- `[model.js:mapAnalystRecord]`
- `[records.js:normalizeEarthquakeSnapshot]`
- `[source.js:createUsgsEarthquakeSource]`

## Invariants
- [index.js:43]: `throw new TypeError('Earthquakes require a snapshot source');`
- [index.js:44]: `if (!overlayHost) throw new TypeError('Earthquakes require an overlay host');`
- [ownership.test.mjs:23]: `import assert from 'node:assert/strict';`
- [ownership.test.mjs:77]: `assert.equal(signal.aborted, true);`
- [ownership.test.mjs:80]: `assert.equal(await pending, false);`
- [records.test.mjs:23]: `import assert from 'node:assert/strict';`
- [records.test.mjs:48]: `assert.equal(Array.isArray(rows), true);`
- [records.test.mjs:49]: `assert.equal(rows.length, 1);`

## Side Effects
- [index.js:182]: `console.warn('[Data:Earthquakes] Fetch error:', e);`
- [index.js:208]: `* objects for the analyst query engine. On-demand only (called at most`
- [index.js:209]: `* once per spoken query) — zero per-frame cost, no listeners, no caching.`
- [model.js:98]: `* (analyst query engine seam). Pure — no Cesium types. Missing/unknown`
- [source.js:28]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:34]: `if (!response.ok) throw new Error(`USGS HTTP ${response.status}`);`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/earthquakes/...`
