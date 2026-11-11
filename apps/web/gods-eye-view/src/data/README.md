# Data

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/data`.

## Interface
- `[adminBoundaries.js:normalizeAdminName]`
- `[adminBoundaries.js:packLoads]`
- `[adminBoundaries.js:decodeRing]`
- `[adminBoundaries.js:pointInRing]`
- `[adminBoundaries.js:polygonsContain]`
- `[adminBoundaries.js:containsAnchor]`
- `[adminBoundaries.js:geometryOf]`
- `[adminBoundaries.js:boxDistanceKm]`
- `[adminBoundaries.js:adminQueryIdentity]`
- `[adminBoundaries.js:parseAdminQuery]`
- `[adminBoundaries.js:rank]`
- `[adminBoundaries.js:findAdminArea]`
- `[adminBoundaries.js:findAdminCandidates]`
- `[adminBoundaries.js:findAdminAreaAt]`
- `[adsbLolFallback.js:normalizeAdsbLolAircraftState]`
- `[adsbLolFallback.js:normalizeAdsbLolPointResponse]`
- `[aircraftClass.js:classifyAircraft]`
- `[aircraftClass.js:AIRCRAFT_CLASS_LABELS]`
- `[aircraftClass.js:CLASS_SCALE_2D]`
- `[aircraftClass.js:CLASS_SCALE_3D]`
- Subdirectory: [local_data](./local_data/README.md)

## Invariants
- [adminBoundaries.test.mjs:26]: `import assert from 'node:assert/strict';`
- [adminBoundaries.test.mjs:54]: `assert.deepEqual(packLoads, { admin1: 0, counties: 0, countries: 0 });`
- [adminBoundaries.test.mjs:55]: `assert.equal(parseAdminQuery('Texas').kind, 'any');`
- [adsbLolFallback.test.mjs:24]: `import assert from 'node:assert/strict';`
- [adsbLolFallback.test.mjs:46]: `assert.equal(state[0], 'a1b2c3');`
- [adsbLolFallback.test.mjs:47]: `assert.equal(state[1], 'UAL123');`
- [aircraftClass.test.mjs:25]: `import assert from 'node:assert/strict';`
- [aircraftClass.test.mjs:29]: `assert.equal(classifyAircraft({ typeCode: 'F16' }), 'fastjet');`
- [aircraftClass.test.mjs:30]: `assert.equal(classifyAircraft({ typeCode: 'EC35' }), 'helicopter');`
- [aircraftEmergency.test.mjs:25]: `import assert from 'node:assert/strict';`

## Side Effects
- [adminBoundaries.js:41]: `*   - `findAdminArea(query, { near })` — name-only. Resolves asks that are`
- [adminBoundaries.test.mjs:70]: `for (const query of [`
- [adminBoundaries.test.mjs:79]: `const unit = await findAdminArea(query, { near: AUSTIN });`
- [adminBoundaries.test.mjs:80]: `assert.equal(unit?.id, 'US-TX', query);`
- [aircraftClass.js:69]: `'EXEC',`
- [aircraftEmergencyAnalyst.test.mjs:325]: `const query = (value) =>`
- [aircraftEmergencyAnalyst.test.mjs:326]: `engine.query({`
- [aircraftEmergencyAnalyst.test.mjs:334]: `const bySquawk = await query('squawk');`
- [aircraftIcons.js:291]: `const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${...`
- [aircraftNearbyPolicy.js:23]: `/** Decide whether a loaded aircraft participates in a proximity query.`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/data/...`
