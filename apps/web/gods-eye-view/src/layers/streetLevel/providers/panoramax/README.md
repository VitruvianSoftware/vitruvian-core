# Panoramax

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/streetLevel/providers/panoramax`.

## Interface
- `[decode.js:simplifyLine]`
- `[decode.js:decodeCoverageTile]`
- `[decode.js:decodeCoverageTileSliced]`
- `[decode.js:decodePictures]`
- `[index.js:panoramaxZoomFor]`
- `[index.js:passesCoverage]`
- `[index.js:pictureTilesAround]`
- `[index.js:createPanoramaxProvider]`
- `[policy.js:PANORAMAX_PROVIDER_ID]`
- `[policy.js:PANORAMAX_NAME]`
- `[policy.js:PANORAMAX_LABEL]`
- `[policy.js:PANORAMAX_API]`
- `[policy.js:PICK_PREFIX]`
- `[policy.js:COLORS]`
- `[policy.js:COVERAGE_Z14_BELOW_M]`
- `[policy.js:COVERAGE_Z13_BELOW_M]`
- `[policy.js:COVERAGE_Z12_BELOW_M]`
- `[policy.js:COVERAGE_Z11_BELOW_M]`
- `[policy.js:COVERAGE_LINES_BELOW_M]`
- `[policy.js:COVERAGE_TUNING]`

## Invariants
- [decode.test.mjs:23]: `import assert from 'node:assert/strict';`
- [decode.test.mjs:67]: `assert.equal(sequences.length, 2);`
- [decode.test.mjs:70]: `assert.equal(pano.isPano, true);`
- [policy.test.mjs:23]: `import assert from 'node:assert/strict';`
- [policy.test.mjs:38]: `assert.equal(COLORS.coverage, '#ff6f00');`
- [policy.test.mjs:39]: `assert.equal(PROVIDER_COLORS.panoramax, '#ff6f00');`
- [provider.test.mjs:23]: `import assert from 'node:assert/strict';`
- [provider.test.mjs:159]: `assert.equal(definition.id, 'panoramax');`
- [provider.test.mjs:160]: `assert.equal(definition.label, 'PANORAMAX');`
- [source.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [policy.js:126]: `* The meta-catalogue speaks HTTP/1.1 only, so the browser opens six`
- [policy.test.mjs:153]: `item.assets.sd.href = 'http://insecure.example/sd.jpg';`
- [policy.test.mjs:278]: `item.links.at(-1).href = 'http://insecure.example';`
- [provider.test.mjs:89]: `nearestItems: async (query) => {`
- [provider.test.mjs:90]: `calls.nearest.push(query);`
- [provider.test.mjs:91]: `const at = { lon: query.lon, lat: query.lat };`
- [source.js:44]: `/** An HTTP or API failure; `retryAfterSec` is set while Panoramax is busy. */`
- [source.js:60]: `* Seconds from a Retry-After header (delay seconds or an HTTP date), or`
- [source.js:121]: `* @param {{fetchImpl?: typeof fetch, api?: string}} [options]`
- [source.test.mjs:37]: `/** A fetch answering from `respond(url)`, recording every URL asked. */`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/streetLevel/providers/panoramax/...`
