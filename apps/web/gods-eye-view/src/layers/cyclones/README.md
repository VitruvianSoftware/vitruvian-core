# Cyclones

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/cyclones`.

## Interface
- `[index.js:createCyclonesLayer]`
- `[labels.js:CYCLONE_OVERLAY_SOURCE_ID]`
- `[labels.js:CYCLONE_LEAD_LABEL_MAX_DISTANCE_M]`
- `[labels.js:CYCLONE_OVERLAY_COHORT_LIMIT]`
- `[labels.js:CYCLONE_ACCENT]`
- `[labels.js:CYCLONE_SELECTED_ACCENT]`
- `[labels.js:CYCLONE_MARKER_PX]`
- `[labels.js:cycloneOverlayEntries]`
- `[labels.js:cycloneStormIdFromEntryId]`
- `[labels.js:createCycloneLabels]`
- `[rendering.js:coherentCycloneGeometry]`
- `[rendering.js:createCycloneRendering]`
- `[source.js:CYCLONE_RESPONSE_LIMIT]`
- `[source.js:validateCycloneSnapshot]`
- `[source.js:createCycloneSource]`

## Invariants
- [coverage.test.mjs:24]: `import assert from 'node:assert/strict';`
- [coverage.test.mjs:87]: `assert.notEqual(translated(), SERVER_COVERAGE, 'es.json has a translation');`
- [coverage.test.mjs:92]: `assert.ok(`
- [index.js:99]: `throw new TypeError('Cyclones require a snapshot source');`
- [index.test.mjs:24]: `import assert from 'node:assert/strict';`
- [index.test.mjs:94]: `assert.ok(canvas);`
- [index.test.mjs:99]: `assert.equal(type, 'left');`
- [labels.test.mjs:24]: `import assert from 'node:assert/strict';`
- [labels.test.mjs:69]: `assert.deepEqual(`
- [labels.test.mjs:82]: `assert.equal(card.cardStyle, 'tactical');`

## Side Effects
- [labels.js:156]: `const match = /^(?:storm|lead):([^:]+)(?::|$)/.exec(String(entryId ?? ''));`
- [source.js:235]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:256]: `throw new Error(`Cyclone HTTP ${response.status}`);`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/cyclones/...`
