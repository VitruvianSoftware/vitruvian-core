# Overlays

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/overlays`.

## Interface
- `[worldOverlay.js:AMBIENT_CARD_COLLISION_CAPACITY]`
- `[worldOverlay.js:WORLD_OVERLAY_PAINT_LANES]`
- `[worldOverlay.js:paintLaneForOverlayEntry]`
- `[worldOverlay.js:normalizeOverlayEntry]`
- `[worldOverlay.js:selectBoundedOverlayCohort]`
- `[worldOverlay.js:registerWorldOverlayPaintLane]`
- `[worldOverlay.js:setOverlayEntries]`
- `[worldOverlay.js:upsertOverlayEntry]`
- `[worldOverlay.js:removeOverlayEntry]`
- `[worldOverlay.js:clearOverlaySource]`
- `[worldOverlay.js:setOverlaySourceVisible]`
- `[worldOverlay.js:getOverlayPaintRect]`
- `[worldOverlay.js:hitTestWorldOverlay]`
- `[worldOverlay.js:getWorldOverlayDiagnostics]`
- `[worldOverlay.js:isOverlayPointVisible]`
- `[worldOverlay.js:subscribeWorldOverlayActions]`
- `[worldOverlay.js:activateWorldOverlayAction]`
- `[worldOverlay.js:initWorldOverlay]`
- `[worldOverlay.js:destroyWorldOverlay]`
- `[worldOverlayChrome.js:WORLD_OVERLAY_OCCLUDER_SELECTORS]`

## Invariants
- [wildlifeSightingOverlay.test.mjs:24]: `import assert from 'node:assert/strict';`
- [wildlifeSightingOverlay.test.mjs:108]: `assert.equal(ctx.text[0], expected);`
- [wildlifeSightingOverlay.test.mjs:109]: `assert.ok(ctx.measureText(ctx.text[0]).width <= 96);`
- [worldOverlay.test.mjs:27]: `import assert from 'node:assert/strict';`
- [worldOverlay.test.mjs:358]: `assert.equal(`
- [worldOverlay.test.mjs:469]: `assert.equal(getWorldOverlayDiagnostics().entryCount, 1);`
- [worldOverlayActionsView.test.mjs:28]: `import assert from 'node:assert/strict';`
- [worldOverlayActionsView.test.mjs:48]: `assert.equal(region.getAttribute('role'), 'region');`
- [worldOverlayActionsView.test.mjs:49]: `assert.equal(region.className, 'world-overlay-accessibility');`
- [worldOverlayAllocation.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [worldOverlayAllocation.test.mjs:339]: `if (result.error) throw new Error(`probe failed to spawn: ${result.error.mess...`
- [worldOverlayDraw.test.mjs:64]: `const match = /rgba\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*([0-9.]+)\s*\)/.exec(`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/overlays/...`
