# Cctv

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/cctv`.

## Interface
- `[cap.js:resolveCatalogCap]`
- `[cap.js:allocateSourceCap]`
- `[catalog.js:createCctvCatalog]`
- `[constants.js:DEFAULT_CCTV_SOURCE_FILE]`
- `[constants.js:DEFAULT_AUSTIN_ROWS_URL]`
- `[constants.js:DEFAULT_AUSTIN_MAX_SOURCES]`
- `[constants.js:CCTV_SHARED_SOURCE_SLOTS]`
- `[constants.js:DEFAULT_CCTV_MAX_SOURCES]`
- `[constants.js:CCTV_MAX_SOURCES_CEILING]`
- `[constants.js:AUSTIN_DOWNTOWN]`
- `[constants.js:TXDOT_CCTV_STATUS_URL]`
- `[constants.js:TXDOT_CCTV_SNAPSHOT_URL]`
- `[constants.js:TXDOT_DISTRICTS]`
- `[constants.js:DEFAULT_TXDOT_DISTRICTS]`
- `[constants.js:DEFAULT_TXDOT_MAX_SOURCES]`
- `[constants.js:TXDOT_ANCHORS]`
- `[constants.js:TXDOT_DISTRICT_ELEVATION_M]`
- `[constants.js:TXDOT_DEFAULT_ELEVATION_M]`
- `[constants.js:CALTRANS_CCTV_URL]`
- `[constants.js:DEFAULT_CALTRANS_DISTRICTS]`

## Invariants
- [ontario511.test.mjs:23]: `import assert from 'node:assert/strict';`
- [ontario511.test.mjs:63]: `assert.deepEqual(await loadOntarioSourcesFromOpenData({}, {}), []);`
- [ontario511.test.mjs:64]: `assert.deepEqual(`

## Side Effects
- [catalog.js:244]: `if (!fs.existsSync(resolved)) return [];`
- [catalog.js:245]: `const raw = fs.readFileSync(resolved, 'utf8');`
- [catalog.js:353]: `// packs aren't forced — the same gate that governed the Austin-only fetch`
- [constants.js:142]: `'https://services.arcgis.com/3wFbqsFPLeKqOlIK/arcgis/rest/services/FL511_Traf...`
- [constants.js:237]: `/** The API lets one certificate and user id fetch a camera once a minute. */`
- [constants.js:282]: `'http://webcam.warendorf.de/',`
- [groundHeights.js:49]: `const stat = fs.statSync(resolved);`
- [groundHeights.js:53]: `const parsed = JSON.parse(fs.readFileSync(resolved, 'utf8'));`
- [lithuania.js:29]: `import { readResponseJsonCapped } from '../common/http.js';`
- [lithuania.js:75]: `// Reconstruct so extra query parameters cannot alter the request.`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/cctv/...`
