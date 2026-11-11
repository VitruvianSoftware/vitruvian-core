# Kartaview

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/streetLevel/providers/kartaview`.

## Interface
- `[decode.js:MAX_TILE_SEGMENTS]`
- `[decode.js:MAX_LINE_POINTS]`
- `[decode.js:tileSegments]`
- `[decode.js:chainSegments]`
- `[decode.js:decodeCoverageTile]`
- `[decode.js:maskedSegments]`
- `[decode.js:readMaskImage]`
- `[index.js:kartaViewZoomFor]`
- `[index.js:createKartaViewProvider]`
- `[policy.js:KARTAVIEW_PROVIDER_ID]`
- `[policy.js:KARTAVIEW_NAME]`
- `[policy.js:KARTAVIEW_LABEL]`
- `[policy.js:KARTAVIEW_API_HOST]`
- `[policy.js:PICK_PREFIX]`
- `[policy.js:COLORS]`
- `[policy.js:COVERAGE_STREET_ZOOM_BELOW_M]`
- `[policy.js:COVERAGE_MAX_HEIGHT_M]`
- `[policy.js:COVERAGE_TUNING]`
- `[policy.js:TOO_HIGH_HINT]`
- `[policy.js:NO_COVERAGE_HINT]`

## Invariants
- [decode.test.mjs:23]: `import assert from 'node:assert/strict';`
- [decode.test.mjs:48]: `assert.equal(sequences.length, 2);`
- [decode.test.mjs:49]: `assert.deepEqual(sequences[0].parts, [`
- [policy.test.mjs:23]: `import assert from 'node:assert/strict';`
- [policy.test.mjs:69]: `assert.equal(photo.id, '7102491');`
- [policy.test.mjs:70]: `assert.equal(photo.sequenceId, '14010');`
- [provider.test.mjs:23]: `import assert from 'node:assert/strict';`
- [provider.test.mjs:167]: `assert.equal(definition.id, 'kartaview');`
- [provider.test.mjs:168]: `assert.equal(definition.requiresKeyId, null);`
- [source.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [index.js:293]: `load: async ({ query, ...tile }, { signal }) =>`
- [index.js:294]: `readMask(await source.getTileMask(tile, query, { signal })),`
- [index.js:295]: `keyOf: ({ query, z, x, y }) => `${query}|${z}/${x}/${y}`,`
- [policy.js:87]: `/** The API is HTTP/1.1 (six connections): tiles 3, lookups 2, pages 1. */`
- [policy.js:192]: `* The query of a filtered PNG coverage tile, or '' when nothing is`
- [policy.js:243]: `/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?/.exec(`
- [policy.test.mjs:102]: `'http://storage1.openstreetcam.org/a.jpg',`
- [policy.test.mjs:112]: `/tracker|javascript|evil|^http:/,`
- [policy.test.mjs:199]: `const [, encoded] = /\/rs:fit:1024:512\/(.+)$/.exec(url);`
- [source.js:52]: `* An HTTP or API failure; `retryAfterSec` is set while KartaView rate-limits,`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/streetLevel/providers/kartaview/...`
