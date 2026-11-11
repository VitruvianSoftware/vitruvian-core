# Vessels

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/vessels`.

## Interface
- `[cameraArea.js:vesselViewArea]`
- `[cards.js:createCards]`
- `[cockpitSubject.js:VESSEL_COCKPIT_LAYER_ID]`
- `[cockpitSubject.js:vesselEyeHeightM]`
- `[cockpitSubject.js:vesselCockpitInfo]`
- `[evidence.js:createEvidence]`
- `[index.js:createVesselLayer]`
- `[ingestion.js:createIngestion]`
- `[ingestion.js:createVesselFeed]`
- `[lifecycle.js:createLifecycle]`
- `[policy.js:FOCUS_EVIDENCE_DEV]`
- `[policy.js:DEFAULT_RENDER_ROWS]`
- `[policy.js:DEFAULT_ACTIVE_LABELS]`
- `[policy.js:REFRESH_MS]`
- `[policy.js:AIS_FIRST_CONNECT_GRACE_MS]`
- `[policy.js:VISIBILITY_UPDATE_MS]`
- `[policy.js:FOCUS_UPDATE_MS]`
- `[policy.js:LABEL_GRID_PX]`
- `[policy.js:CARD_MIN_SEP_PX]`
- `[policy.js:TRAIL_COLOR]`

## Invariants
- [cockpitSubject.test.mjs:26]: `import assert from 'node:assert/strict';`
- [cockpitSubject.test.mjs:34]: `assert.equal(vesselEyeHeightM('71'), 30, 'cargo');`
- [cockpitSubject.test.mjs:35]: `assert.equal(vesselEyeHeightM('84'), 30, 'tanker');`
- [ingestion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ingestion.test.mjs:80]: `assert.equal(probe.applied.length, 0);`
- [ingestion.test.mjs:81]: `assert.equal(probe.labels.length, 0);`
- [ownership.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ownership.test.mjs:122]: `assert.notEqual(one[key], two[key]);`
- [ownership.test.mjs:123]: `assert.notEqual(one.state.records.byMmsi, two.state.records.byMmsi);`
- [radarContacts.test.mjs:27]: `import assert from 'node:assert/strict';`

## Side Effects
- [ingestion.js:57]: `// can't wedge the poll indefinitely (parity with the track fetch + flights).`
- [ingestion.test.mjs:107]: `async getSnapshot(query) {`
- [ingestion.test.mjs:108]: `assert.equal(query.maxRows, 500);`
- [ingestion.test.mjs:139]: `getSnapshot: async (query) => {`
- [queries.js:194]: `* (analyst query engine seam). Pure — no Cesium types. Missing/unknown`
- [queries.js:299]: `* @param {string|number} query MMSI or partial vessel name.`
- [queries.js:302]: `findByQuery(query) {`
- [rendering.js:217]: `const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" v...`
- [testing.js:124]: `/** Exercise the request-owned live loader with a test-controlled fetch. */`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/vessels/...`
