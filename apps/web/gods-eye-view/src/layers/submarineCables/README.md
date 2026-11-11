# Submarinecables

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/submarineCables`.

## Interface
- `[bundledSource.js:createBundledCableSource]`
- `[geometry.js:featureReference]`
- `[geometry.js:featureLabel]`
- `[geometry.js:normalizeFeatures]`
- `[index.js:createSubmarineCableLayer]`
- `[ingestion.js:createIngestion]`
- `[interaction.js:createInteraction]`
- `[lifecycle.js:createLifecycle]`
- `[overlay.js:selectCableReferenceLabelWinners]`
- `[overlay.js:cableReferencePriority]`
- `[overlay.js:createCableOverlayEntry]`
- `[overlay.js:createCableOverlayPublisher]`
- `[overlay.js:createCableReferenceSweepGate]`
- `[overlay.js:updateCableReferenceStem]`
- `[overlay.js:clampLabel]`
- `[policy.js:BASE_CABLE_COLOR]`
- `[policy.js:BASE_LANDING_COLOR]`
- `[policy.js:STEM_TARGET_PX]`
- `[policy.js:CABLE_REFERENCE_LABEL_MAX_DISTANCE_M]`
- `[policy.js:CABLE_REFERENCE_LABEL_WINNER_CAP]`

## Invariants
- [bundledSource.test.mjs:24]: `import assert from 'node:assert/strict';`
- [bundledSource.test.mjs:40]: `await assert.rejects(source.fetch(), /HTTP 503/);`
- [bundledSource.test.mjs:41]: `assert.equal(released, 2);`

## Side Effects
- [bundledSource.js:42]: `fetchImpl = (...args) => fetch(...args),`
- [bundledSource.js:53]: `throw new Error(`HTTP ${response.status} for ${url}`);`
- [bundledSource.js:61]: `async fetch(signal) {`
- [bundledSource.test.mjs:40]: `await assert.rejects(source.fetch(), /HTTP 503/);`
- [bundledSource.test.mjs:55]: `await assert.rejects(source.fetch(controller.signal), { name: 'AbortError' });`
- [index.js:36]: `if (!source?.fetch || !source.label)`
- [index.js:38]: `'A cable source with a label and fetch(signal) is required',`
- [ingestion.js:69]: `({ cables: cableJson, landingPoints: landingJson } = await source.fetch(`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/submarineCables/...`
