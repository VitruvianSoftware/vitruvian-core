# Wind

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/wind`.

## Interface
- `[fields.js:SCALAR_UNAVAILABLE]`
- `[fields.js:WIND_FIELDS]`
- `[fields.js:windTrailColor]`
- `[fields.js:trailEraseAlpha]`
- `[fields.js:sampleScalar]`
- `[fields.js:createFieldRaster]`
- `[gpuRendering.js:createWindGpuRendering]`
- `[index.js:formatWindValidTime]`
- `[index.js:windStats]`
- `[index.js:createWindLayer]`
- `[inspection.js:WIND_UNITS]`
- `[inspection.js:windFrom]`
- `[inspection.js:formatWindSpeed]`
- `[inspection.js:inspectWindAtCenter]`
- `[inspectionMarker.js:createWindInspectionMarker]`
- `[model.js:normalizeLongitude]`
- `[model.js:sampleWind]`
- `[model.js:metersPerDegreeLon]`
- `[model.js:windSpeed]`
- `[model.js:windColor]`

## Invariants
- [fieldUnavailableLocale.test.mjs:26]: `import assert from 'node:assert/strict';`
- [fieldUnavailableLocale.test.mjs:38]: `assert.deepEqual(english, []);`
- [fieldUnavailableLocale.test.mjs:46]: `assert.equal(fieldUnavailableText('constructor'), null);`
- [fields.test.mjs:24]: `import assert from 'node:assert/strict';`
- [fields.test.mjs:46]: `assert.equal(sampleScalar(snapshot, 0, 90, 'speed'), 5);`
- [fields.test.mjs:47]: `assert.equal(sampleScalar(snapshot, 0, 90, 'temperature'), 0);`
- [gpuRendering.test.mjs:24]: `import assert from 'node:assert/strict';`
- [gpuRendering.test.mjs:53]: `assert.ok(!this.destroyed, 'owned resource destroyed once');`
- [gpuRendering.test.mjs:83]: `assert.ok(!this.destroyed, 'owned resource destroyed once');`
- [index.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [index.js:54]: `* HTTP status line carries a number, so it goes back onto a placeholder.`
- [index.js:57]: `const http = /^Wind HTTP (\d+)$/.exec(problem);`
- [index.js:58]: `if (http)`
- [presentation.js:66]: `const match = /^(-?\d+(?:\.\d+)?) (°C|hPa)$/.exec(reading.scalarValue);`
- [presentation.js:89]: `const match = /^(\d+(?:\.\d+)?)°([NS]) · (\d+(?:\.\d+)?)°([EW])$/.exec(`
- [presentation.js:116]: `const match = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}) UTC$/.exec(validTime || '');`
- [rendering.js:296]: `function spawn(particle, scene, occluder) {`
- [rendering.js:316]: `for (const particle of particles) spawn(particle, scene, occluder);`
- [source.js:32]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:41]: `const query = `model=${model}${overlay === 'none' ? '' : `&overlay=${overlay}...`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/wind/...`
