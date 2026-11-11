# Airquality

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/airQuality`.

## Interface
- `[index.js:createAirQualityLayer]`
- `[model.js:AIR_QUALITY_BANDS]`
- `[model.js:AIR_QUALITY_UNKNOWN_COLOR]`
- `[model.js:AIR_QUALITY_OVERLAY_SOURCE_ID]`
- `[model.js:AIR_QUALITY_OVERLAY_COHORT_LIMIT]`
- `[model.js:AIR_QUALITY_OVERLAY_COLLISION_CAPACITY]`
- `[model.js:OBSERVATION_MAX_AGE_MS]`
- `[model.js:STALE_AFTER_MS]`
- `[model.js:newestObservation]`
- `[model.js:readingsAreStale]`
- `[model.js:AIR_QUALITY_PROVIDERS]`
- `[model.js:airQualityBandById]`
- `[model.js:airQualityColor]`
- `[model.js:aqhiDisplayValue]`
- `[model.js:bandForValue]`
- `[model.js:valueLabel]`
- `[model.js:bandRiskText]`
- `[model.js:normalizeAqhiStations]`
- `[model.js:normalizeAqhiObservations]`
- `[model.js:createAirQualityOverlayEntry]`

## Invariants
- [airQualityLocale.test.mjs:25]: `import assert from 'node:assert/strict';`
- [airQualityLocale.test.mjs:74]: `assert.notEqual(t('Air quality'), 'Air quality', 'catalog has the entry');`
- [airQualityLocale.test.mjs:75]: `assert.equal(layerNameForId('air-quality'), t('Air quality'));`
- [model.test.mjs:23]: `import assert from 'node:assert/strict';`
- [model.test.mjs:79]: `assert.equal(row.provider, 'eccc');`
- [model.test.mjs:80]: `assert.equal(row.scale, 'AQHI');`
- [ownership.test.mjs:23]: `import assert from 'node:assert/strict';`
- [ownership.test.mjs:79]: `assert.throws(() => createAirQualityLayer(), /snapshot source/);`
- [ownership.test.mjs:80]: `assert.throws(`
- [source.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [airQualityLocale.test.mjs:116]: `test(`${locale}: the Weather card shows an HTTP failure as the row does`, asy...`
- [airQualityLocale.test.mjs:119]: `throw new Error('ECCC HTTP 503');`
- [airQualityLocale.test.mjs:126]: `inLocale(locale, () => translateFeedError('ECCC HTTP 503')),`
- [index.js:287]: `* Snapshot readings as JSON-safe records for the analyst query engine.`
- [ownership.test.mjs:205]: `throw new Error('ECCC HTTP 503');`
- [ownership.test.mjs:282]: `if (fail) throw new Error('ECCC HTTP 503');`
- [source.js:56]: `* @param {Function} [options.fetchImpl] - Injected fetch, for tests.`
- [source.js:62]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:85]: `if (!response.ok) throw new Error(`ECCC HTTP ${response.status}`);`
- [source.test.mjs:48]: `/** A fetch that serves the station catalog and observations from mutable sta...`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/airQuality/...`
