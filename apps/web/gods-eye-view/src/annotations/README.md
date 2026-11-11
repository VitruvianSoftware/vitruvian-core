# Annotations

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/annotations`.

## Interface
- `[annotationEngine.js:resolveOutlineWithRetry]`
- `[annotationEngine.js:normalizeTargetKey]`
- `[annotationEngine.js:createAnnotationEngine]`
- `[annotationEngine.js:promoteStreetHighlight]`
- `[annotationResolver.js:selectFootprint]`
- `[drawMarks.js:DRAW_COLORS]`
- `[drawMarks.js:DRAW_COLOR_CSS]`
- `[drawMarks.js:DRAW_COLOR_NAMES]`
- `[drawMarks.js:drawMarkFallbackName]`
- `[drawMarks.js:drawMarkGeometry]`
- `[drawMarks.js:drawMarkActions]`
- `[drawMarks.js:drawMarkActionsFor]`
- `[drawMarks.js:presentDrawMarks]`
- `[drawMode.js:DRAW_SHAPES]`
- `[drawMode.js:MIN_VERTICES]`
- `[drawMode.js:MAX_VERTICES]`
- `[drawMode.js:normalizeShape]`
- `[drawMode.js:createDrawSession]`
- `[drawMode.js:addVertex]`
- `[drawMode.js:isFiniteCoordinate]`

## Invariants
- [adminOutline.test.mjs:26]: `import assert from 'node:assert/strict';`
- [adminOutline.test.mjs:90]: `assert.ok(resolved, target);`
- [adminOutline.test.mjs:91]: `assert.equal(resolved.source, 'bundled', target);`
- [annotationEngine.test.mjs:38]: `import assert from 'node:assert/strict';`
- [annotationEngine.test.mjs:139]: `assert.equal(fp, FP);`
- [annotationEngine.test.mjs:140]: `assert.equal(calls.count, 1);`
- [annotationResolver.test.mjs:37]: `import assert from 'node:assert/strict';`
- [annotationResolver.test.mjs:80]: `assert.equal(fp, null); // keep the honest point anchor`
- [annotationResolver.test.mjs:87]: `assert.ok(fp, 'expected the true monument way to be accepted');`
- [drawMarks.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [adminOutline.test.mjs:55]: `async geocode(query) {`
- [adminOutline.test.mjs:56]: `geocodes.push(query);`
- [adminOutline.test.mjs:131]: `for (const [query, viewer, latitude] of [`
- [annotationEngine.js:81]: `// blip) aborts the client fetch, but the /api/overpass proxy keeps the upstream`
- [annotationEngine.js:166]: `// Generation token + in-flight fetch controllers guard against clear / new-t...`
- [annotationEngine.test.mjs:310]: `test('outline queue: clear drops queued-but-unstarted upgrades without a late...`
- [annotationEngine.test.mjs:381]: `test('retry: HTTP 429 Retry-After 5s gets one ladder-spaced retry; a second 4...`
- [annotationEngine.test.mjs:383]: `const originalFetch = globalThis.fetch;`
- [annotationResolver.test.mjs:74]: `// The real enclosing grounds polygon — unnamed overlap with the monument query.`
- [annotationResolver.test.mjs:207]: `const originalFetch = globalThis.fetch;`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/annotations/...`
