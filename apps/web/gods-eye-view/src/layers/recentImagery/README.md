# Recentimagery

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/recentImagery`.

## Interface
- `[catalog.js:fetchCmrPages]`
- `[catalog.js:parseCmrUmm]`
- `[catalog.js:cmrSearchUrl]`
- `[catalog.js:searchHls]`
- `[display.js:displayDay]`
- `[display.js:displayMetres]`
- `[display.js:READOUT_WORDS]`
- `[index.js:FOCUS_DEBOUNCE_MS]`
- `[index.js:SPLIT_PUBLISH_MS]`
- `[index.js:MODES]`
- `[index.js:createRecentImageryLayer]`
- `[model.js:CATALOG_DAYS]`
- `[model.js:PRODUCTS]`
- `[model.js:boxSideKm]`
- `[model.js:validateBox]`
- `[model.js:viewTooLargeMessage]`
- `[model.js:fitViewHeightM]`
- `[model.js:boxCentre]`
- `[model.js:boxFromPin]`
- `[model.js:boxFromRectangle]`

## Invariants
- [catalog.test.mjs:24]: `import assert from 'node:assert/strict';`
- [catalog.test.mjs:126]: `assert.equal(hits, 9);`
- [catalog.test.mjs:127]: `assert.deepEqual(granules[0], {`
- [cmr-raw-page-budget.test.mjs:24]: `import assert from 'node:assert/strict';`
- [cmr-raw-page-budget.test.mjs:53]: `assert.equal(calls, 2);`
- [cmr-raw-page-budget.test.mjs:54]: `assert.equal(result.granules.length, 200);`
- [imagery-box-missing-edge.test.mjs:24]: `import assert from 'node:assert/strict';`
- [imagery-box-missing-edge.test.mjs:36]: `assert.equal(validateBox(box).ok, false);`
- [imagery-box-missing-edge.test.mjs:37]: `assert.equal(validateBox(box).reason, 'invalid');`
- [index.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [catalog.js:54]: `* @param {{ product: string, url: string, fetchImpl: typeof fetch, signal?: A...`
- [catalog.js:74]: `throw new Error(`HTTP ${response?.status ?? 'error'} from CMR`);`
- [catalog.js:177]: `* @param {{ product: string, box: object, startIso: string, endIso: string }}...`
- [catalog.test.mjs:160]: `test('the CMR query names the collection, box, window and page size with lite...`
- [catalog.test.mjs:213]: `{ product: 'L30', message: 'HTTP 503 from CMR' },`
- [model.js:278]: `const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day));`
- [model.js:312]: `const match = /^\d{4}-(\d{2})-(\d{2})$/.exec(String(day || ''));`
- [model.js:331]: `const match = /^(S30|L30|VIIRS):(\d{4}-\d{2}-\d{2})$/.exec(String(key));`
- [source.js:32]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:40]: `searchHls: (query) => search({ ...query, fetchImpl }),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/recentImagery/...`
