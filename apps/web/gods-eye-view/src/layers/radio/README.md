# Radio

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/radio`.

## Interface
- `[catalogModel.js:createCatalogModel]`
- `[categories.js:createCategories]`
- `[clustering.js:createClustering]`
- `[controls.js:createControls]`
- `[index.js:createRadioLayer]`
- `[ingestion.js:createIngestion]`
- `[interaction.js:createInteraction]`
- `[labels.js:createLabels]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:createModel]`
- `[navigation.js:createNavigation]`
- `[playback.js:createPlayback]`
- `[policy.js:RADIO_PREFIX]`
- `[policy.js:DIRECTORY_ENDPOINT]`
- `[policy.js:HORIZON_TICK_MS]`
- `[policy.js:HORIZON_CAMERA_MOVE_EPSILON_M]`
- `[policy.js:MARKER_LIFT_M]`
- `[policy.js:SELECTED_LIFT_M]`
- `[policy.js:RADIO_TUNER_DIRECTORY_LIMIT]`
- `[policy.js:RADIO_TUNER_STATION_LIMIT]`

## Invariants
- [ingestionErrors.i18n.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ingestionErrors.i18n.test.mjs:112]: `assert.equal(layerState._error, expected);`
- [ingestionErrors.i18n.test.mjs:117]: `assert.notEqual(shown, expected, `${locale}: ${name}`);`
- [source.test.mjs:24]: `import assert from 'node:assert/strict';`
- [source.test.mjs:39]: `assert.deepEqual(`
- [source.test.mjs:44]: `assert.deepEqual(`

## Side Effects
- [labels.js:226]: `return `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBo...`
- [queries.js:76]: `const query = parts.categories.normalizeRadioTag(stationQuery);`
- [queries.js:92]: `if (query) {`
- [queries.js:102]: `parts.categories.normalizeRadioTag(value).includes(query),`
- [source.js:27]: `fetchImpl = (...args) => globalThis.fetch(...args),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/radio/...`
