# Packs

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/scenes/packs`.

## Interface
- `[defaults.js:createDefaultScenePacks]`
- `[nepal.js:nepalScenePresentation]`
- `[registry.js:createScenePackRegistry]`

## Invariants
- [registry.test.mjs:24]: `import assert from 'node:assert/strict';`
- [registry.test.mjs:66]: `assert.equal(shotRuntimeDurationSec(scene, shot, packs), 10);`
- [registry.test.mjs:67]: `assert.equal(effectiveShotHoldSec(scene, shot, packs), 8);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/scenes/packs/...`
