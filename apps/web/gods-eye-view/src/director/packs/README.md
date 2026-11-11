# Packs

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/director/packs`.

## Interface
- `[geojson.js:decodePackGeoJSON]`
- `[manifest.js:PACK_LIMITS]`
- `[manifest.js:validateAssetPath]`
- `[manifest.js:validateDataPack]`
- `[manifest.js:validateSceneDataPacks]`
- `[session.js:createDataPackSession]`
- `[source.js:createAssetDirectorySource]`

## Invariants
- [asset-stream-cancellation.test.mjs:24]: `import assert from 'node:assert/strict';`
- [asset-stream-cancellation.test.mjs:59]: `if (cancel) await assert.rejects(pending, { name: 'AbortError' });`
- [asset-stream-cancellation.test.mjs:60]: `else assert.deepEqual([...(await pending).bytes], [1, 2]);`
- [geojson.js:68]: `throw new Error('Features require distinct string IDs');`
- [packs.test.mjs:24]: `import assert from 'node:assert/strict';`
- [packs.test.mjs:65]: `assert.deepEqual(`
- [packs.test.mjs:69]: `assert.deepEqual(normalized.scenes[0].shots[0].dataPackIds, ['outline']);`

## Side Effects
- [manifest.js:93]: `'expected an HTTPS source link without credentials, query or fragment',`
- [source.js:28]: `fetchImpl = globalThis.fetch,`
- [source.js:32]: `!['https:', 'http:'].includes(base.protocol) ||`
- [source.js:40]: `'Asset source requires an explicit HTTP(S) directory URL',`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/director/packs/...`
