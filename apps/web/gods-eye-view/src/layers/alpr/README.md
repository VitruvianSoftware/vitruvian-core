# Alpr

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/alpr`.

## Interface
- `[floors.js:createAlprFloorResolver]`
- `[index.js:createAlprCamerasLayer]`
- `[model.js:destinationPointDeg]`
- `[model.js:alprCreditMarkup]`
- `[overlay.js:createAlprOverlay]`
- `[policy.js:LAYER_ID]`
- `[policy.js:OVERPASS_URL]`
- `[policy.js:REQUEST_DEBOUNCE_MS]`
- `[policy.js:MAX_VIEWPORT_DEGREES]`
- `[policy.js:QUERY_LIMIT]`
- `[policy.js:DETAIL_MIN_ZOOM]`
- `[policy.js:DETAIL_MAX_ZOOM]`
- `[policy.js:DETAIL_MAX_TILES]`
- `[policy.js:SOURCE_RECORD_LIMIT]`
- `[policy.js:PRECISION_CACHE_LIMIT]`
- `[policy.js:MAX_RENDERED]`
- `[policy.js:DIRECTION_CONE_M]`
- `[policy.js:DIRECTION_CONE_HALF_ANGLE_DEG]`
- `[policy.js:EARTH_MEAN_RADIUS_M]`
- `[policy.js:QUERY_SNAP_DEGREES]`

## Invariants
- [overlay.test.mjs:24]: `import assert from 'node:assert/strict';`
- [overlay.test.mjs:152]: `assert.equal(h.draw.length, 2);`
- [overlay.test.mjs:153]: `assert.ok(h.draw[0].endsWith('alpr-marker-selected.png'));`
- [source.test.mjs:24]: `import assert from 'node:assert/strict';`
- [source.test.mjs:49]: `await assert.rejects(source.fetch(bad), /bounded city viewport/);`
- [source.test.mjs:51]: `assert.equal(calls, 0);`

## Side Effects
- [index.js:56]: `if (typeof source?.fetch !== 'function')`
- [index.js:76]: `/** Whether the query hit QUERY_LIMIT — the view likely holds more cameras th...`
- [index.js:90]: `/** Snapped box of the last successful query; a view still inside it reuses i...`
- [policy.js:68]: `/** Query boxes are snapped outward to this grid so nearby camera moves reuse`
- [policy.js:72]: `/** A view still fully inside the last snapped query box reuses those records`
- [records.js:41]: `* Snap a viewport box OUTWARD to the query grid, clamped to valid ranges.`
- [records.js:138]: `* Exported so the query shape is pinnable.`
- [source.js:95]: `tileFetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:118]: `async fetch(box, signal) {`
- [source.js:224]: `fetchImpl = (...args) => globalThis.fetch(...args),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/alpr/...`
