# Ghostmaps

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/ghostMaps`.

## Interface
- `[catalog.js:GHOSTMAPS_REPO]`
- `[catalog.js:GHOSTMAPS_MAX_FILE_BYTES]`
- `[catalog.js:GHOSTMAPS_PRODUCTS]`
- `[catalog.js:GHOSTMAPS_LATEST_DROP]`
- `[catalog.js:parseGhostMapsEdition]`
- `[catalog.js:ghostMapsFileTitle]`
- `[catalog.js:buildGhostMapsCatalog]`
- `[catalog.js:ghostMapsRawUrl]`
- `[catalog.js:parseGitRefAdvertisement]`
- `[index.js:GHOSTMAPS_LAYER_ID]`
- `[index.js:GHOSTMAPS_OVERLAY_SOURCE_ID]`
- `[index.js:createGhostMapsLayer]`
- `[kml.js:MAX_GHOSTMAPS_FEATURES]`
- `[kml.js:MAX_GHOSTMAPS_POSITIONS]`
- `[kml.js:parseKmlCoordinates]`
- `[kml.js:readGhostMapsKml]`
- `[records.js:decodeHtmlEntities]`
- `[records.js:htmlToText]`
- `[records.js:GHOSTMAPS_DEFAULT_AGE_DAYS]`
- `[records.js:GHOSTMAPS_AGE_OPTIONS]`

## Invariants
- [catalog.test.mjs:24]: `import assert from 'node:assert/strict';`
- [catalog.test.mjs:44]: `assert.deepEqual(`
- [catalog.test.mjs:50]: `assert.deepEqual(`
- [lifecycle.test.mjs:23]: `import assert from 'node:assert/strict';`
- [lifecycle.test.mjs:183]: `assert.equal(created.length, 0);`
- [lifecycle.test.mjs:184]: `assert.equal(revoked.length, 0);`
- [records.test.mjs:24]: `import assert from 'node:assert/strict';`
- [records.test.mjs:49]: `assert.equal(parseGhostMapsEventDate(value), Date.parse(iso), value);`
- [records.test.mjs:64]: `assert.equal(parseGhostMapsEventDate(value), null, value);`

## Side Effects
- [catalog.js:150]: `const match = DATE_IN_NAME.exec(stem);`
- [catalog.js:161]: `const edition = Number(EDITION_IN_NAME.exec(tail)?.[1] ?? 0);`
- [catalog.js:252]: `* The branch head from a git smart-HTTP ref advertisement`
- [catalog.test.mjs:174]: `test('the branch head comes from the smart-HTTP ref advertisement', () => {`
- [records.js:104]: `/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)...`
- [records.js:108]: `/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?(?:Z|[...`
- [records.test.mjs:110]: `const ARCGIS = `<html xmlns:fo="http://www.w3.org/1999/XSL/Format"><head>`
- [records.test.mjs:111]: `<META http-equiv="Content-Type" content="text/html"></head>`
- [records.test.mjs:135]: `test('ArcGIS popup tables become plain label/value fields and http links', ()...`
- [source.js:38]: `fetchImpl = (...args) => globalThis.fetch(...args),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/ghostMaps/...`
