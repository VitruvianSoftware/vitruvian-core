# Inaturalist

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/inaturalist`.

## Interface
- `[client.js:inatRetryCooldownMs]`
- `[client.js:createInatClient]`
- `[grid.fixture.mjs:syntheticGrid]`
- `[grid.js:INAT_GRID_DECODE_MEASURE]`
- `[grid.js:validInatGridTile]`
- `[grid.js:projectInatGrid]`
- `[observations.js:inaturalistProxy]`
- `[proxy.fixture.mjs:NOW]`
- `[proxy.fixture.mjs:installInatProxy]`
- `[queue.js:createInatQueue]`

## Invariants
- [client.test.mjs:24]: `import assert from 'node:assert/strict';`
- [client.test.mjs:62]: `assert.deepEqual(`
- [client.test.mjs:75]: `assert.deepEqual(result.rows, []);`
- [grid.test.mjs:24]: `import assert from 'node:assert/strict';`
- [grid.test.mjs:37]: `assert.equal(raw.grid.length, 64);`
- [grid.test.mjs:38]: `assert.ok(raw.grid.every((row) => row.length === 64));`
- [observations.test.mjs:24]: `import assert from 'node:assert/strict';`
- [observations.test.mjs:83]: `assert.fail('expected fake upstream calls were not dispatched');`
- [observations.test.mjs:95]: `assert.equal(options.redirect, 'error');`
- [proxy.fixture.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [client.js:27]: `import { readResponseJsonCapped } from '../common/http.js';`
- [client.js:28]: `import { clampInt } from '../common/query.js';`
- [client.js:52]: `/** Seconds and HTTP dates are accepted; a missing value earns one minute. */`
- [client.test.mjs:127]: `/status=503 reason=http/,`
- [grid.test.mjs:203]: `'sec-fetch-site': 'cross-site',`
- [grid.test.mjs:211]: `for (const query of [`
- [grid.test.mjs:220]: `const result = await request(`/grid?${query}`);`
- [observations.js:24]: `import { coalesceProxyRequest } from '../common/http.js';`
- [observations.js:26]: `import { requiredFiniteQueryNumber } from '../common/query.js';`
- [observations.js:46]: `function requestParams(pathname, query, nowMs) {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/inaturalist/...`
