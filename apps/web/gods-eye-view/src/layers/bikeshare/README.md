# Bikeshare

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/bikeshare`.

## Interface
- `[controls.js:createControls]`
- `[index.js:createBikeshareLayer]`
- `[ingestion.js:createIngestion]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:createModel]`
- `[policy.js:BIKESHARE_SELECTED_OVERLAY_SOURCE_ID]`
- `[policy.js:BIKESHARE_SELECTED_OVERLAY_SOURCE_OPTIONS]`
- `[policy.js:ACTIVATION_ENTER_ALTITUDE_M]`
- `[policy.js:ACTIVATION_EXIT_ALTITUDE_M]`
- `[policy.js:CAMERA_DEBOUNCE_MS]`
- `[policy.js:CITY_RANGE_BASE_KM]`
- `[policy.js:STATUS_POLL_MS]`
- `[policy.js:POINT_SIZE_MIN]`
- `[policy.js:POINT_SIZE_MAX]`
- `[policy.js:DEFAULT_CAPACITY]`
- `[policy.js:POINT_HEIGHT_OFFSET_M]`
- `[policy.js:MAX_TOTAL_POINTS]`
- `[policy.js:COLOR_GREEN]`
- `[policy.js:COLOR_YELLOW]`
- `[policy.js:COLOR_RED]`

## Invariants
- [barcelonaSystems.test.mjs:23]: `import assert from 'node:assert/strict';`
- [barcelonaSystems.test.mjs:67]: `assert.ok(system, `${id} is registered`);`
- [barcelonaSystems.test.mjs:68]: `assert.equal(system.provider, expected.provider);`
- [brPbscCities.test.mjs:23]: `import assert from 'node:assert/strict';`
- [brPbscCities.test.mjs:75]: `assert.ok(city, `${id} is registered`);`
- [brPbscCities.test.mjs:76]: `assert.equal(city.provider, 'Bike Itaú');`
- [failureReporting.test.mjs:37]: `import assert from 'node:assert/strict';`
- [failureReporting.test.mjs:67]: `assert.equal(stats.count, 1069);`
- [failureReporting.test.mjs:68]: `assert.equal(`
- [latamPbscCities.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [barcelonaSystems.test.mjs:125]: `assert.equal(isAllowedGbfsHost('gbfs.nextbike.net.example'), false);`
- [controls.js:49]: `* query engine. On demand only (once per spoken query); [] while the`
- [controls.js:104]: `stats.error = msg('GBFS fetch error');`
- [failureReporting.test.mjs:81]: `assert.equal(stats.error, 'GBFS fetch error');`
- [failureReporting.test.mjs:94]: `assert.equal(methods.getStats().error, 'GBFS fetch error');`
- [failureReporting.test.mjs:152]: `if (source.dead.has(id)) throw new Error('GBFS HTTP 404');`
- [ingestion.js:57]: `* Fetch and parse JSON from a GBFS endpoint via the local proxy.`
- [ingestion.js:62]: `* @throws {Error} On non-OK HTTP status or malformed JSON.`
- [ingestion.js:103]: `* @throws {Error} On unknown city, fetch failure, or empty station list.`
- [proxyRoute.test.mjs:78]: `* Mount the GBFS proxy the way the dev server does and return a fetch-shaped`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/bikeshare/...`
