# Mapillary

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/streetLevel/providers/mapillary`.

## Interface
- `[coverageFixture.mjs:zigzag]`
- `[coverageFixture.mjs:layerWriter]`
- `[coverageFixture.mjs:lineGeometry]`
- `[coverageFixture.mjs:encodeCoverageTile]`
- `[decode.js:decodeCoverageTile]`
- `[index.js:createMapillaryProvider]`
- `[policy.js:MAPILLARY_PROVIDER_ID]`
- `[policy.js:MAPILLARY_NAME]`
- `[policy.js:MAPILLARY_LABEL]`
- `[policy.js:MAPILLARY_KEY_ID]`
- `[policy.js:MAPILLARY_GRAPH_HOST]`
- `[policy.js:MAPILLARY_SOURCE_METHODS]`
- `[policy.js:PICK_PREFIX]`
- `[policy.js:COLORS]`
- `[policy.js:KEY_REJECTED_MESSAGE]`
- `[policy.js:RATE_LIMITED_MESSAGE]`
- `[policy.js:COVERAGE_TUNING]`
- `[policy.js:SEQUENCE_IMAGES_LIMIT]`
- `[policy.js:MAPILLARY_CREDIT_HTML]`
- `[policy.js:mapillaryImageUrl]`

## Invariants
- [decode.test.mjs:23]: `import assert from 'node:assert/strict';`
- [decode.test.mjs:124]: `assert.equal(decoded.sequences.length, 1);`
- [decode.test.mjs:126]: `assert.equal(sequence.id, 'seq-42');`
- [mapillary.test.mjs:23]: `import assert from 'node:assert/strict';`
- [mapillary.test.mjs:30]: `assert.equal(`
- [mapillary.test.mjs:34]: `assert.equal(mapillaryImageUrl('  '), 'https://www.mapillary.com/app/');`
- [provider.test.mjs:23]: `import assert from 'node:assert/strict';`
- [provider.test.mjs:50]: `assert.doesNotThrow(() => validateProviders([def]));`
- [provider.test.mjs:51]: `assert.equal(def.id, 'mapillary');`
- [source.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [source.js:29]: `/** HTTP error flagged `keyRequired`, `keyRejected` or `retryAfterSec` (429). */`
- [source.js:55]: ``${label} HTTP ${response.status}`,`
- [source.js:79]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.test.mjs:163]: `const url = new URL(calls[0].url, 'http://localhost');`
- [viewer.js:46]: `globalThis.location?.href || 'http://localhost/',`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/streetLevel/providers/mapillary/...`
