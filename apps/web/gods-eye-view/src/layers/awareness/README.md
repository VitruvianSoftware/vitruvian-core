# Awareness

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/awareness`.

## Interface
- `[controls.js:createControls]`
- `[dependencies.js:createDependencies]`
- `[focus.js:createFocus]`
- `[history.js:createHistory]`
- `[index.js:createAwarenessLayer]`
- `[ingestion.js:createIngestion]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:createModel]`
- `[navigation.js:createNavigation]`
- `[panel.js:formatAwarenessCount]`
- `[panel.js:presentAwarenessDistance]`
- `[panel.js:createPanel]`
- `[policy.js:AIRCRAFT_DEPENDENCIES]`
- `[policy.js:DEPENDENCIES]`
- `[policy.js:AWARENESS_REFRESH_MS]`
- `[policy.js:AWARENESS_MOTION_REFRESH_MS]`
- `[policy.js:AWARENESS_MOTION_SETTLE_MS]`
- `[policy.js:AWARENESS_REEVALUATE_DISTANCE_M]`
- `[policy.js:AWARENESS_PAGE_ROTATE_MS]`
- `[policy.js:AWARENESS_PAGE_SIZE]`

## Invariants
- [anchor.test.mjs:24]: `import assert from 'node:assert/strict';`
- [anchor.test.mjs:67]: `assert.equal(anchors.length, 1);`
- [anchor.test.mjs:68]: `assert.ok(anchors[0] instanceof Cesium.Cartesian3);`
- [directionOverlay.test.mjs:28]: `import assert from 'node:assert/strict';`
- [directionOverlay.test.mjs:97]: `assert.deepEqual(views, [null]);`
- [directionOverlay.test.mjs:100]: `assert.ok(view.container === container);`
- [panel.test.mjs:24]: `import assert from 'node:assert/strict';`
- [panel.test.mjs:55]: `assert.deepEqual(`
- [presentation.test.mjs:24]: `import assert from 'node:assert/strict';`
- [presentation.test.mjs:28]: `assert.equal(formatAwarenessDirection(359.4), '359');`

## Side Effects
- [queries.js:64]: `//     Overpass fetch, so the lifecycle stays `enabling` for that whole window`
- [queries.js:65]: `//     however long the fetch takes. Confirmed live: a held 17 s first fetch`
- [queries.js:139]: `// of the retained square used to fetch installation tiles.`
- [queries.test.mjs:101]: `assert.equal(moved.count, 1, 'west site leaves the radius before the fetch an...`
- [rangeRing.test.mjs:71]: `* by reason. `reducedMotion` stubs the media query for the length of the`
- [rangeRing.test.mjs:80]: `const query = legacyQuery`
- [rangeRing.test.mjs:101]: `? query`
- [subject.js:45]: `const within = WITHIN_KM_RE.exec(label);`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/awareness/...`
