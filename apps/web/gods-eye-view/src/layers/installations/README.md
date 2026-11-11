# Installations

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/installations`.

## Interface
- `[classLabel.js:installationTitle]`
- `[classLabel.js:installationClassLabel]`
- `[controls.js:createControls]`
- `[index.js:createInstallationsLayer]`
- `[ingestion.js:retainNamedHandoff]`
- `[ingestion.js:createIngestion]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:createModel]`
- `[namedMarkers.js:createNamedMarkers]`
- `[policy.js:LAYER_ID]`
- `[policy.js:REQUEST_DEBOUNCE_MS]`
- `[policy.js:MAX_RENDERED]`
- `[policy.js:GOOGLE_MILITARY_PLACE_TYPES]`
- `[policy.js:COLOR_BY_CLASS]`
- `[policy.js:EARTH_MEAN_RADIUS_M]`
- `[policy.js:DISTANCE_PREFILTER_MARGIN_M]`
- `[policy.js:ANCHOR_REFRESH_M]`
- `[rendering.js:createRendering]`
- `[selection.js:createSelection]`
- `[source.js:installationResponseSaturated]`

## Invariants
- [classLabel.packClasses.test.mjs:26]: `import assert from 'node:assert/strict';`
- [classLabel.packClasses.test.mjs:52]: `assert.deepEqual(`
- [ingestion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ingestion.test.mjs:67]: `assert.equal(searches.length, 1);`
- [ingestion.test.mjs:69]: `assert.ok(Math.abs(latitude + 16.9) < 1e-9);`
- [installationFeedbackLocale.test.mjs:24]: `import assert from 'node:assert/strict';`
- [installationFeedbackLocale.test.mjs:42]: `assert.notEqual(empty, 'No mapped sites in view');`
- [installationFeedbackLocale.test.mjs:48]: `assert.notEqual(found, '2 mapped sites in view');`
- [lifecycle.test.mjs:24]: `import assert from 'node:assert/strict';`
- [lifecycle.test.mjs:85]: `assert.equal(state.dataSource.show, true);`

## Side Effects
- [controls.js:111]: `// Keep the live centre even when the coarse fetch anchor has not moved.`
- [controls.js:251]: `* query engine. On demand only (once per spoken query); [] while the`
- [ingestion.js:100]: `// Guidance, not a fault: the layer chose not to query because the view is`
- [ingestion.test.mjs:47]: `searchNearby: async (query) => {`
- [ingestion.test.mjs:48]: `searches.push(query);`
- [lifecycle.js:61]: `// Cached markers and geometry become visible before the next fetch.`
- [lifecycle.js:80]: `// the first fetch. Avoid racing it with a second aborting request here.`
- [lifecycle.test.mjs:87]: `// No renderRecords or successful fetch occurs between toggles.`
- [namesLoading.test.mjs:134]: `t.mock.method(globalThis, 'fetch', async (_url, options) => {`
- [source.js:113]: `fetchImpl = (...args) => globalThis.fetch(...args),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/installations/...`
