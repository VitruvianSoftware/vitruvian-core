# Osmplaces

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/osmPlaces`.

## Interface
- `[index.js:createOsmPlacesLayer]`
- `[model.js:OSM_PLACES_LAYER_ID]`
- `[model.js:mapOsmFeature]`
- `[model.js:dedupeOsmRecords]`

## Invariants
- [index.test.mjs:28]: `import assert from 'node:assert/strict';`
- [index.test.mjs:60]: `assert.deepEqual(layer.getAnalystRecords(), [], 'off: nothing to count');`
- [index.test.mjs:61]: `assert.equal(layer.getStats().count, 2);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/osmPlaces/...`
