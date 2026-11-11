# Gnss

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/gnss`.

## Interface
- `[index.js:defaultGnssViewAnchor]`
- `[index.js:createGnssIntegrityLayer]`
- `[records.js:GNSS_NIC_THRESHOLD]`
- `[records.js:GNSS_NACP_THRESHOLD]`
- `[records.js:GNSS_CELL_DEG]`
- `[records.js:GNSS_MIN_AIRCRAFT]`
- `[records.js:GNSS_WINDOW_MS]`
- `[records.js:GNSS_MEDIUM_PERCENT]`
- `[records.js:GNSS_HIGH_PERCENT]`
- `[records.js:GNSS_ANOMALY_STATE]`
- `[records.js:GNSS_NOMINAL_STATE]`
- `[records.js:GNSS_INTERPRETATION]`
- `[records.js:GNSS_CLASSIFIER]`
- `[records.js:gnssProvenance]`
- `[records.js:GNSS_PROVENANCE]`
- `[records.js:normalizeGnssAircraft]`
- `[records.js:gnssCellKey]`
- `[records.js:accumulateGnssObservations]`
- `[records.js:pruneGnssObservations]`
- `[records.js:gnssIntegrityLevel]`

## Invariants
- [ownership.test.mjs:23]: `import assert from 'node:assert/strict';`
- [ownership.test.mjs:114]: `assert.deepEqual(pixel, new Cesium.Cartesian2(500, 400));`
- [ownership.test.mjs:122]: `assert.ok(Math.abs(anchor.latitude - 30) < 1e-8);`
- [records.test.mjs:23]: `import assert from 'node:assert/strict';`
- [records.test.mjs:89]: `assert.deepEqual(rows, [`
- [records.test.mjs:118]: `assert.equal(normalizeGnssAircraft({}), null);`
- [source.test.mjs:23]: `import assert from 'node:assert/strict';`
- [source.test.mjs:32]: `assert.ok(options.signal instanceof AbortSignal);`
- [source.test.mjs:45]: `assert.deepEqual(calls, ['/api/gnss-integrity?lat=50&lon=20']);`
- [sourceErrorLocale.test.mjs:25]: `import assert from 'node:assert/strict';`

## Side Effects
- [index.js:354]: `console.warn('[Data:GNSS] Fetch error:', e);`
- [ownership.test.mjs:106]: `test('a globe-wide rectangle uses the visible screen centre as the query anch...`
- [ownership.test.mjs:166]: `assert.equal(calls, 2, 'nearby views reuse the same query region');`
- [ownership.test.mjs:235]: `assert.equal(await layer.update(), false, 'disabled layers do not fetch');`
- [source.js:43]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:66]: `// HTTP errors are matched by FEED_ERROR_PATTERNS in ui/statusText.js.`
- [source.js:68]: `? msg('GNSS feed rate limited (HTTP 429)')`
- [source.test.mjs:81]: `/HTTP 502/,`
- [source.test.mjs:100]: `test('HTTP failures distinguish rate limiting, preserve Retry-After and class...`
- [sourceErrorLocale.test.mjs:24]: `// card's info line shows them in the UI language, the HTTP form included.`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/gnss/...`
