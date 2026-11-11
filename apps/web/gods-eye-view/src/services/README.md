# Services

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/services`.

## Interface
- `[application.js:applicationServices]`
- `[application.js:configureApplicationServices]`
- `[groundFloor.js:createGroundFloor]`
- `[groundSnap.js:createGroundSnap]`
- `[meshFloorSampler.js:createMeshFloorSampler]`
- `[requests.js:createApplicationRequestServices]`
- `[terrainHeights.js:DEFAULT_MAX_CACHE_ENTRIES]`
- `[terrainHeights.js:createTerrainHeights]`

## Invariants
- [boundary-probe-recovery.test.mjs:24]: `import assert from 'node:assert/strict';`
- [boundary-probe-recovery.test.mjs:45]: `assert.deepEqual(await services.boundaries.query('fixture'), []);`
- [boundary-probe-recovery.test.mjs:46]: `assert.deepEqual(await services.boundaries.query('fixture'), []);`
- [groundSnap.test.mjs:23]: `import assert from 'node:assert/strict';`
- [groundSnap.test.mjs:59]: `assert.equal(viewer.calls.samples, 4, 'four samples per 250 ms window');`
- [groundSnap.test.mjs:62]: `assert.equal(`
- [meshFloorSampler.js:191]: `// coordinate and require its `geometricError` to be below a threshold tied`
- [requests.test.mjs:24]: `import assert from 'node:assert/strict';`
- [requests.test.mjs:38]: `assert.match(requests[0].url, /^\/custom\/region\?latitude=30.00000&longitude...`
- [requests.test.mjs:39]: `assert.deepEqual(await services.terrain.getHeights([{ lat: 30, lon: -97 }]), ...`

## Side Effects
- [application.js:32]: `boundaries: ['query'],`
- [boundary-probe-recovery.test.mjs:45]: `assert.deepEqual(await services.boundaries.query('fixture'), []);`
- [boundary-probe-recovery.test.mjs:46]: `assert.deepEqual(await services.boundaries.query('fixture'), []);`
- [boundary-probe-recovery.test.mjs:50]: `(await services.boundaries.query('fixture')).code,`
- [meshFloorSampler.js:109]: `* sampleHeight is a CPU-side query against loaded tiles.`
- [requests.js:37]: `fetchImpl = (...args) => fetch(...args),`
- [requests.js:110]: `return null; // capability unknown: let this query ask the server`
- [requests.js:135]: `async query(query, { signal } = {}) {`
- [requests.test.mjs:27]: `test('independent compatible endpoints receive normalized requests without ch...`
- [requests.test.mjs:29]: `const original = globalThis.fetch;`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/services/...`
