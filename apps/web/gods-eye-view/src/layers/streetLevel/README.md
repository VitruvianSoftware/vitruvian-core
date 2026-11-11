# Streetlevel

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/streetLevel`.

## Interface
- `[cameraFraming.js:createCameraFraming]`
- `[credits.js:createCredits]`
- `[filter.js:normalizeFilter]`
- `[filter.js:sameFilter]`
- `[filter.js:resolveFilter]`
- `[filter.js:passesImageryFilter]`
- `[glyphs.js:imageConeGlyph]`
- `[glyphs.js:viewConeMarkerGlyph]`
- `[glyphs.js:positionMarkerGlyph]`
- `[groundClick.js:groundClickHeightOk]`
- `[groundClick.js:createGroundClick]`
- `[imageSize.js:imageSize]`
- `[index.js:createStreetLevelLayer]`
- `[limiter.js:createLimiter]`
- `[lineCoverage.js:ZOOM_IN_HINT]`
- `[lineCoverage.js:sequenceIdFromPick]`
- `[lineCoverage.js:freshCoverage]`
- `[lineCoverage.js:coverageZoom]`
- `[lineCoverage.js:createLineCoverage]`
- `[marker.js:createMarker]`
- Subdirectory: [providers](./providers/README.md)

## Invariants
- [cameraFraming.test.mjs:23]: `import assert from 'node:assert/strict';`
- [cameraFraming.test.mjs:64]: `assert.equal(flights.length, 1);`
- [cameraFraming.test.mjs:65]: `assert.ok(Math.abs(heightOf(flights[0].sphere.center) - 123) < 0.01);`
- [filter.test.mjs:23]: `import assert from 'node:assert/strict';`
- [filter.test.mjs:37]: `assert.deepEqual(normalizeFilter({ pano: 'pano' }, current), {`
- [filter.test.mjs:41]: `assert.deepEqual(normalizeFilter({ pano: 'sideways' }, current), current);`
- [groundClick.test.mjs:23]: `import assert from 'node:assert/strict';`
- [groundClick.test.mjs:95]: `assert.equal(opened.length, 1, JSON.stringify(picked));`
- [groundClick.test.mjs:96]: `assert.ok(near(opened[0].point));`
- [imageSize.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [glyphs.js:28]: `const markup = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" heigh...`
- [index.test.mjs:135]: `if (!up) throw new TypeError('fetch failed');`
- [lineCoverage.js:320]: `// Fetch and the one-time terrain-height table load run side by side,`
- [photoViewer.js:88]: `typeof globalThis.fetch === 'function'`
- [photoViewer.js:137]: `const response = await fetch(url, {`
- [photoViewer.js:167]: `// A size refusal stays one: the viewer must not fetch it another way.`
- [photoViewer.test.mjs:309]: `fetch: globalThis.fetch,`
- [photoViewer.test.mjs:317]: `(globalThis.fetch = async () => ({`
- [photoViewer.test.mjs:340]: `globalThis.fetch = async () => ({`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/streetLevel/...`
