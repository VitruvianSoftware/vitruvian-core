# Wildlifesightings

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/wildlifeSightings`.

## Interface
- `[acartiaTaxa.js:ACARTIA_GUARD_BOX]`
- `[acartiaTaxa.js:ACARTIA_CETACEAN_NAMES]`
- `[acartiaTaxa.js:acartiaSpeciesGroup]`
- `[acartiaTaxa.js:inAcartiaCoverage]`
- `[billboardModel.js:createWildlifeBillboardModel]`
- `[bounds.js:WILDLIFE_MAX_VIEW_DEGREES]`
- `[bounds.js:snapWildlifeBox]`
- `[cards.js:WILDLIFE_OVERLAY_SOURCE_ID]`
- `[cards.js:WILDLIFE_LABEL_SOURCE_ID]`
- `[cards.js:WILDLIFE_SELECTED_SOURCE_ID]`
- `[cards.js:WILDLIFE_LABEL_SOURCE_OPTIONS]`
- `[cards.js:WILDLIFE_OVERLAY_SOURCE_OPTIONS]`
- `[cards.js:WILDLIFE_SELECTED_SOURCE_OPTIONS]`
- `[cards.js:wildlifeAccent]`
- `[cards.js:ambientScore]`
- `[cards.js:wildlifeLabelScore]`
- `[cards.js:selectWildlifeAmbientRows]`
- `[cards.js:wildlifeCommonName]`
- `[cards.js:wildlifeDisplayName]`
- `[cards.js:buildWildlifeLabelEntry]`

## Invariants
- [acartiaTaxa.test.mjs:24]: `import assert from 'node:assert/strict';`
- [acartiaTaxa.test.mjs:28]: `assert.equal(Object.isFrozen(ACARTIA_CETACEAN_NAMES), true);`
- [acartiaTaxa.test.mjs:29]: `assert.throws(() => ACARTIA_CETACEAN_NAMES.push('Whale shark'), TypeError);`
- [acquisition.test.mjs:23]: `import assert from 'node:assert/strict';`
- [acquisition.test.mjs:184]: `assert.equal(h.chip().state, 'error');`
- [acquisition.test.mjs:185]: `assert.equal(h.layer.getStats().retryInSec, 30);`
- [cache.integration.test.mjs:23]: `import assert from 'node:assert/strict';`
- [cache.integration.test.mjs:89]: `assert.equal(first.cells.length, 2);`
- [cache.integration.test.mjs:91]: `assert.equal(upstreamCalls, 1);`
- [cards.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [acquisition.test.mjs:228]: `assert.equal(h.state.query, null);`
- [acquisition.test.mjs:360]: `throw Object.assign(new Error('iNaturalist HTTP 502'), {`
- [acquisition.test.mjs:388]: `assert.match(chip.title, /iNaturalist HTTP 502.*click to retry/);`
- [bounds.js:30]: `* span too: a legal raw box may expand past the supported query size. */`
- [cache.integration.test.mjs:33]: `// Only the HTTP transport and upstream data are synthetic; no socket is needed.`
- [controls.js:254]: `!state.query &&`
- [density.js:91]: ``<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><defs><radi...`
- [gridViewport.js:157]: `const match = /^grid:(\d+)\/(\d+)\/(\d+):(\d+):(\d+)$/.exec(id);`
- [gridViewport.test.mjs:121]: `test('grid camera viewport supports globe and antimeridian without detail-que...`
- [index.js:99]: `query: null,`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/wildlifeSightings/...`
