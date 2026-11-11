# Datapacks

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/scenes/dataPacks`.

## Interface
- `[controller.js:createSceneDataPacks]`
- `[geometry.js:renderPackGeometry]`
- `[presentation.js:createPackPresentations]`

## Invariants
- [presentation.test.mjs:24]: `import assert from 'node:assert/strict';`
- [presentation.test.mjs:48]: `assert.fail('No entity should be acquired');`
- [presentation.test.mjs:64]: `const rejected = assert.rejects(rendering, /abort/i);`
- [presentationView.test.mjs:28]: `import assert from 'node:assert/strict';`
- [presentationView.test.mjs:74]: `assert.equal($('[data-director-packs]'), null);`
- [presentationView.test.mjs:78]: `assert.equal(panel.tagName, 'DIV');`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/scenes/dataPacks/...`
