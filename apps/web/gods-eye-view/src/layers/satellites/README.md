# Satellites

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/satellites`.

## Interface
- `[catalog.js:createCatalog]`
- `[classes.js:SATELLITE_CLASS_IDS]`
- `[classes.js:DEFAULT_SATELLITE_CLASSES]`
- `[classes.js:SATELLITE_CLASS_DISPLAY]`
- `[classes.js:UNIDENTIFIED_GRACE_YEARS]`
- `[classes.js:PRESUMED_DEAD_AFTER_YEARS]`
- `[classes.js:classifySatellite]`
- `[classes.js:satelliteClassEnterable]`
- `[classes.js:mergeClassVisibility]`
- `[classes.js:OWNER_COUNTRY_CODES]`
- `[classes.js:ownerFromUcs]`
- `[classes.js:ownerFromSatcat]`
- `[classes.js:satelliteOwner]`
- `[classes.js:satelliteOperator]`
- `[classes.js:cosparIdFromTleLine1]`
- `[classes.js:tleEpochMs]`
- `[classes.js:parseSatcatCsv]`
- `[cockpitSubject.js:SATELLITE_COCKPIT_LAYER_ID]`
- `[cockpitSubject.js:COCKPIT_ORBIT_DIM_FACTOR]`
- `[cockpitSubject.js:applyOrbitPathAlpha]`

## Invariants
- [classes.test.mjs:24]: `import assert from 'node:assert/strict';`
- [classes.test.mjs:48]: `assert.deepEqual(SATELLITE_CLASS_IDS, [`
- [classes.test.mjs:56]: `assert.deepEqual(`
- [cockpitSubject.test.mjs:23]: `import assert from 'node:assert/strict';`
- [cockpitSubject.test.mjs:217]: `assert.equal(f.methods.getCockpitSubject(), null);`
- [cockpitSubject.test.mjs:218]: `assert.equal(f.methods.getCockpitPosition(), null);`
- [ingestion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ingestion.test.mjs:115]: `assert.deepEqual(`
- [ingestion.test.mjs:123]: `assert.deepEqual([...state._points.keys()], [100000, 110001, 339999]);`
- [nearestPositions.test.mjs:27]: `import assert from 'node:assert/strict';`

## Side Effects
- [catalog.js:103]: ``[Data:Satellites] Dense group '${DENSE_GROUP_PATH}' fetch failed (${res.stat...`
- [classes.js:143]: `/^(SENTINEL|LANDSAT|WORLDVIEW|GEOEYE|PLEIADES|SPOT[ -]\d|ICEYE|CAPELLA|UMBRA|...`
- [classes.js:175]: `const match = /^(\d{4})-/.exec(String(launchDate || ''));`
- [controls.js:310]: `* @param {string|number} query NORAD id or partial name.`
- [controls.js:313]: `findByQuery(query) {`
- [controls.js:315]: `query === null ||`
- [ingestion.js:455]: `console.warn('[Data:Satellites] Fetch error:', e);`
- [orbits.js:271]: `function resolveSatelliteForPass(query) {`
- [orbits.js:272]: `const text = String(query ?? '').trim();`
- [orbits.js:306]: `* @param {string} query Mission or payload name.`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/satellites/...`
