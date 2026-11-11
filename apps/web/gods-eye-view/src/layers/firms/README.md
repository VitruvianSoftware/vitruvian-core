# Firms

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/firms`.

## Interface
- `[anchors.js:FIRE_ANCHOR_LIFT_M]`
- `[anchors.js:createFireAnchors]`
- `[cards.js:createCards]`
- `[heatImagery.js:createHeatImagery]`
- `[index.js:createFirmsHelpers]`
- `[index.js:createFirmsHeatmapLayer]`
- `[ingestion.js:createIngestion]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:createModel]`
- `[policy.js:REFRESH_INTERVAL_MS]`
- `[policy.js:LOD_LEVELS]`
- `[policy.js:HEAT_RASTER]`
- `[policy.js:HANDOFF_FADE]`
- `[policy.js:HEAT_REBUILD_MS]`
- `[policy.js:LOD_CHECK_MS]`
- `[policy.js:LOD_HYSTERESIS]`
- `[policy.js:VIEW_PADDING]`
- `[policy.js:CONTEXT_TOP_N]`
- `[policy.js:MAX_AMBIENT_LABELS]`
- `[policy.js:LABEL_MIN_SEP_PX]`

## Invariants
- [heatImagery.test.mjs:24]: `import assert from 'node:assert/strict';`
- [heatImagery.test.mjs:77]: `assert.equal(h.layers.length, 1);`
- [heatImagery.test.mjs:78]: `assert.deepEqual(h.layers[0].provider.options.rectangle, { max: true });`
- [heatVisibility.test.mjs:24]: `import assert from 'node:assert/strict';`
- [heatVisibility.test.mjs:58]: `assert.equal(`
- [heatVisibility.test.mjs:65]: `assert.equal(shown, true, 'nonempty sets still resume their raster');`
- [index.js:41]: `throw new TypeError('Fires require a snapshot source');`
- [source.test.mjs:24]: `import assert from 'node:assert/strict';`
- [source.test.mjs:32]: `await assert.rejects(source.getSnapshot(), /Malformed fire snapshot/);`
- [source.test.mjs:45]: `assert.deepEqual(await source.getSnapshot(), { keyRequired: true });`

## Side Effects
- [ingestion.js:114]: `* the heatmap, the context store, the top-fires query and the analyst`
- [ingestion.js:134]: `* are regenerated every fetch, so object/index identity cannot be used.`
- [lifecycle.js:74]: `// near-side ones hidden) until the fetch resolves.`
- [model.js:51]: `* analyst record (analyst query engine seam). Pure — no Cesium types.`
- [queries.js:313]: `* objects for the analyst query engine. Walks the FRP-sorted index so`
- [queries.js:316]: `* most once per spoken query) — zero per-frame cost, no listeners, no`
- [source.js:25]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:44]: `throw new Error(`FIRMS HTTP ${response.status}`);`
- [source.test.mjs:49]: `new RegExp(`FIRMS HTTP ${status}`),`
- [state.js:61]: `/** Surfaced error string when the live fetch failed outright. */`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/firms/...`
