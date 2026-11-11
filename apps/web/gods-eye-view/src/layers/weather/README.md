# Weather

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/weather`.

## Interface
- `[clock.js:RADAR_MAX_GAP_MS]`
- `[clock.js:REGIONAL_INFRARED_MAX_GAP_MS]`
- `[clock.js:GLOBAL_INFRARED_MAX_GAP_MS]`
- `[clock.js:LIGHTNING_MAX_GAP_MS]`
- `[clock.js:PLAY_WAIT_MS]`
- `[clock.js:createWeatherClock]`
- `[display.js:weatherDisplay]`
- `[display.js:insideExtent]`
- `[display.js:escapeCreditText]`
- `[imageryHost.js:resolveImageryHost]`
- `[imageryHost.js:NO_IMAGERY_HOST]`
- `[imageryHost.js:imageryHostStatus]`
- `[imageryOrder.js:orderWeatherImagery]`
- `[index.js:createWeatherLayer]`
- `[infraredAlpha.js:INFRARED_ALPHA_T0]`
- `[infraredAlpha.js:INFRARED_ALPHA_T1]`
- `[infraredAlpha.js:infraredAlpha]`
- `[infraredImage.js:MAX_MOSAIC_BYTES]`
- `[infraredImage.js:processInfraredImage]`
- `[infraredImage.js:decodeInfraredImage]`

## Invariants
- [clock.test.mjs:24]: `import assert from 'node:assert/strict';`
- [clock.test.mjs:107]: `assert.deepEqual(clock.getTimeline(), [-180, -60, 0, 5, 10].map(time));`
- [clock.test.mjs:108]: `assert.equal(clock.selectFor('radar', time(9)), time(0));`
- [display.test.mjs:24]: `import assert from 'node:assert/strict';`
- [display.test.mjs:204]: `/** Assert the built-in description of a product, field by field. */`
- [display.test.mjs:208]: `assert.equal(controls.summary.units, expected.units);`
- [imageryHost.test.mjs:24]: `import assert from 'node:assert/strict';`
- [imageryHost.test.mjs:32]: `assert.equal(imageryHostStatus({ kind: 'tileset' }), null);`
- [imageryHost.test.mjs:33]: `assert.equal(imageryHostStatus({ kind: 'globe' }), null);`
- [imageryOrder.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [display.js:71]: `const match = SCALE_NUMBER.exec(label);`
- [index.js:37]: `* A stored (English) failure in the language. HTTP failures from source.js`
- [index.js:42]: `const http = /^Weather (image )?HTTP (\d+)$/.exec(problem);`
- [index.js:43]: `if (http) {`
- [infraredImage.js:82]: `/** Fetch one capped whole-extent frame, or a `bbox` detail window of it, and...`
- [infraredImage.js:105]: `if (!response.ok) throw new Error(`Weather HTTP ${response.status}`);`
- [infraredImage.test.mjs:80]: `test('mosaic fetch is capped at 4 MiB, forwards cancellation, and releases de...`
- [shellRendering.js:426]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [shellRendering.js:450]: `// The detail window for the shown bounds, the image drawn in it and its fetch.`
- [source.js:131]: `fetchImpl = (...args) => globalThis.fetch(...args),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/weather/...`
