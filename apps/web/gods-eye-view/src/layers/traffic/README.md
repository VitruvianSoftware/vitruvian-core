# Traffic

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/traffic`.

## Interface
- `[animation.js:createAnimation]`
- `[controls.js:createControls]`
- `[flow.js:createFlow]`
- `[flowDecode.js:decodeFlowTile]`
- `[flowSource.js:createFlowTileSource]`
- `[footprint.js:convexFootprint]`
- `[footprint.js:footprintTiles]`
- `[footprint.js:createReticleFootprint]`
- `[index.js:createTrafficLayer]`
- `[ingestion.js:cacheRoadSnapshot]`
- `[ingestion.js:createIngestion]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:createModel]`
- `[policy.js:ACTIVATION_ALTITUDE]`
- `[policy.js:FAST_FETCH_ALTITUDE]`
- `[policy.js:FETCH_DEBOUNCE]`
- `[policy.js:DOT_HEIGHT_OFFSET]`
- `[policy.js:OVERLAP_THRESHOLD]`
- `[policy.js:MAX_DOTS]`
- `[policy.js:roadDotBudget]`

## Invariants
- [deadline.test.mjs:24]: `import assert from 'node:assert/strict';`
- [deadline.test.mjs:56]: `assert.equal(options.signal.aborted, true);`
- [deadline.test.mjs:57]: `assert.equal(h.state._fetching, false);`
- [footprint.test.mjs:24]: `import assert from 'node:assert/strict';`
- [footprint.test.mjs:46]: `assert.ok(tiles.length < bbox.length);`
- [footprint.test.mjs:48]: `assert.ok(b.west <= 0 && b.east >= 0 && b.south <= 0 && b.north >= 0);`
- [hostModes.test.mjs:26]: `import assert from 'node:assert/strict';`
- [hostModes.test.mjs:73]: `assert.equal(normalizeRoadModes(undefined), TRAFFIC_ROAD_MODES);`
- [hostModes.test.mjs:74]: `assert.deepEqual(normalizeRoadModes(['hybrid', 'tomtom']), [`
- [motion.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [animation.js:74]: `* Spawn animated dot primitives along a single road.`
- [animation.js:89]: `// byte-identical): closures spawn nothing, congestion colors/slows dots.`
- [animation.js:127]: `// Jam-viz density prototype: jam-road dots spawn as bumper-to-bumper`
- [flow.js:46]: `* Map a failed flow fetch onto one short, honest user-facing reason.`
- [flow.js:53]: `* @param {Error|{name?:string, message?:string}|null|undefined} error - Rejec...`
- [flow.js:54]: `* @returns {string|null} Short reason, or null for an aborted (superseded) fe...`
- [flowDecode.js:27]: `* @file TomTom traffic-flow vector-tile client: fetch + MVT decode.`
- [flowSource.js:80]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [flowSource.js:89]: `allowedOrigin: 'http://localhost',`
- [flowSource.js:110]: `new Error(`TomTom flow unavailable (HTTP ${response.status})`),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/traffic/...`
