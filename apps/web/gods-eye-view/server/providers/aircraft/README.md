# Aircraft

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/aircraft`.

## Interface
- `[adsb-lol.js:adsbLolProxy]`
- `[enrichment.js:adsbdbProxy]`
- `[opensky.js:openSkyClientCredentials]`
- `[opensky.js:getOpenSkyToken]`
- `[opensky.js:adsbLolFallbackAnchor]`
- `[opensky.js:openSkyProxy]`
- `[tracks.js:trackBackfillProxies]`

## Invariants
- [openskyCredentials.test.mjs:24]: `import assert from 'node:assert/strict';`
- [openskyCredentials.test.mjs:36]: `const read = () => assert.fail('the file is not read when env vars are set');`
- [openskyCredentials.test.mjs:37]: `assert.deepEqual(`

## Side Effects
- [adsb-lol.js:26]: `} from '../common/http.js';`
- [adsb-lol.js:32]: `* fails — a thrown fetch OR a non-OK status such as 429 — the proxy serves its`
- [adsb-lol.js:56]: `/** Upstream deadline (ms); the fetch previously had none and could hang a po...`
- [enrichment.js:25]: `import { readResponseJsonCapped } from '../common/http.js';`
- [enrichment.js:59]: `await fsp.writeFile(CACHE_PATH, JSON.stringify(cache), 'utf8');`
- [enrichment.js:111]: `const res = await fetch(url, { signal });`
- [opensky.js:31]: `} from '../common/http.js';`
- [opensky.js:32]: `import { requiredFiniteQueryNumber } from '../common/query.js';`
- [opensky.js:49]: `/** @type {number} HTTP status of the cached response. */`
- [tracks.js:24]: `import { readCappedResponseText } from '../common/http.js';`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/aircraft/...`
