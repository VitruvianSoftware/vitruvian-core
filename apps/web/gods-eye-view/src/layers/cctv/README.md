# Cctv

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/cctv`.

## Interface
- `[calibration.js:createCalibration]`
- `[cards.js:createCards]`
- `[catalog.js:createCatalog]`
- `[controls.js:createControls]`
- `[frames.js:fitToProjection]`
- `[frames.js:createFrames]`
- `[geometry.js:createGeometry]`
- `[geometryQueue.js:createGeometryQueue]`
- `[ground.js:createGround]`
- `[headingConfidence.js:isHeadingEstimated]`
- `[headingConfidence.js:headingHudToken]`
- `[health.js:createHealth]`
- `[hover.js:createHover]`
- `[index.js:createCctvLayer]`
- `[ingestion.js:createIngestion]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:createModel]`
- `[modelSpecs.js:lookupModelSpec]`
- `[modelSpecs.js:horizontalFovRangeDeg]`
- `[modelSpecs.js:fixedHorizontalFovDeg]`

## Invariants
- [frames.test.mjs:27]: `import assert from 'node:assert/strict';`
- [frames.test.mjs:38]: `assert.equal(PROJECTION_CANVAS_WIDTH, 1920);`
- [frames.test.mjs:39]: `assert.equal(PROJECTION_CANVAS_HEIGHT, 1080);`
- [headingConfidence.test.mjs:28]: `import assert from 'node:assert/strict';`
- [headingConfidence.test.mjs:32]: `assert.equal(isHeadingEstimated({ headingConfidence: 'low' }), true);`
- [headingConfidence.test.mjs:36]: `assert.equal(isHeadingEstimated({ headingConfidence: ' LOW ' }), true);`
- [modelSpecs.test.mjs:28]: `import assert from 'node:assert/strict';`
- [modelSpecs.test.mjs:41]: `assert.ok(spec);`
- [modelSpecs.test.mjs:42]: `assert.equal(spec.brand, 'Axis');`
- [presentation.i18n.test.mjs:26]: `import assert from 'node:assert/strict';`

## Side Effects
- [calibration.js:266]: `* re-fetch, no store touch.`
- [cards.js:377]: `/** Stops the pacer and detaches all in-flight fetch handlers. */`
- [cards.js:398]: `* cache, and fetch telemetry. Nothing leaks across a toggle.`
- [frames.js:262]: `* Triggers a new frame fetch for an image-mode projection if the refresh`
- [frames.js:271]: `// Hidden-state gate (perf wave 2): no new frame fetch/decode for a canvas`
- [geometry.js:463]: `// query and no shared-cell write (aircraft floors stay untouched).`
- [ground.js:185]: `* chunked, geoid fallback; NOT a scene query). The catalog's orthometric`
- [ground.js:350]: `* scene query), then re-applies the geometry so the rigid lift accounts for`
- [hover.js:122]: `* Fast-tracked frame fetch for the hover-summoned card: launches`
- [hover.js:124]: `* user-gesture fetch is fine even during the geometry drain), but still`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/cctv/...`
