# Standalone

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/standalone`.

## Interface
- `[application.js:createStandaloneApplication]`
- `[catalog.js:createStandaloneCatalog]`
- `[catalog.js:getStandaloneCatalog]`
- `[controls.js:createStandaloneControls]`
- `[data.js:createStandaloneData]`
- `[layerSources.js:createStandaloneLayerSources]`
- `[scene.js:createStandaloneScene]`
- `[startupChrome.js:startStandaloneChrome]`
- `[toolCatalog.js:loadToolCatalog]`
- `[tools.js:createStandaloneTools]`

## Invariants
- [layerSources.test.mjs:24]: `import assert from 'node:assert/strict';`
- [layerSources.test.mjs:52]: `assert.equal(mapTiles.length, 2);`
- [layerSources.test.mjs:53]: `assert.notEqual(mapTiles[0], mapTiles[1]);`
- [startupChrome.test.mjs:24]: `import assert from 'node:assert/strict';`
- [startupChrome.test.mjs:102]: `assert.deepEqual(f.events, []);`
- [startupChrome.test.mjs:105]: `assert.deepEqual(f.events, ['hidden']);`

## Side Effects
- [layerSources.js:72]: `origin: () => globalThis.document?.baseURI ?? 'http://localhost',`
- [toolCatalog.js:40]: `fetchImpl: (...args) => globalThis.fetch(...args),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/standalone/...`
