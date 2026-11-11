# Search

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/search`.

## Interface
- `[alpsGeocoder.js:createAlpsGeocoder]`
- `[coordinateGeocoder.js:createCoordinateGeocoder]`
- `[coordinateParser.js:formatCoordinateLabel]`
- `[coordinateParser.js:parseCoordinateQuery]`
- `[defaults.js:createDefaultPlaceSearch]`
- `[defaults.js:defaultGeospatial]`
- `[geospatial.js:validCoordinate]`
- `[geospatial.js:createGeospatialServices]`
- `[google.js:normalizeGooglePlace]`
- `[google.js:createGoogleGeocoder]`
- `[http.js:normalizeGoogleReverse]`
- `[http.js:createHttpGeospatialProvider]`
- `[nominatim.js:createNominatimProvider]`
- `[placeSearch.js:unavailablePlaceSearch]`
- `[placeSearch.js:createPlaceSearch]`
- `[presetGeocoder.js:createPresetGeocoder]`

## Invariants
- [coordinate-empty-components.test.mjs:24]: `import assert from 'node:assert/strict';`
- [coordinate-empty-components.test.mjs:28]: `assert.equal(parseCoordinateQuery(q), null, q);`
- [coordinate-empty-components.test.mjs:30]: `assert.deepEqual(`
- [coordinateParser.js:90]: `// component; require an unambiguous split rather than guessing its owner.`
- [coordinateParser.test.mjs:30]: `import assert from 'node:assert/strict';`
- [coordinateParser.test.mjs:37]: `assert.deepEqual(parseCoordinateQuery('43.1731, -79.0384'), {`
- [coordinateParser.test.mjs:42]: `assert.deepEqual(parseCoordinateQuery('43.1731,-79.0384')?.lat, 43.1731);`
- [geospatial.test.mjs:24]: `import assert from 'node:assert/strict';`
- [geospatial.test.mjs:66]: `assert.equal((await service.geocode('Town')).place.lat, 30);`
- [geospatial.test.mjs:67]: `assert.equal((await service.reverseGeocode(30, -97)).locality, 'Town');`

## Side Effects
- [alpsGeocoder.js:32]: `async geocode(query, { signal } = {}) {`
- [alpsGeocoder.js:34]: `const name = String(query ?? '')`
- [coordinateGeocoder.js:47]: `* Answer a decimal-degree or geo-URI query without asking anyone.`
- [coordinateGeocoder.js:52]: `* had nothing to say — it is not a verdict on the query.`
- [coordinateGeocoder.js:56]: `async geocode(query, { signal } = {}) {`
- [coordinateParser.js:53]: `const match = COMPONENT.exec(String(text).trim());`
- [coordinateParser.js:78]: `function splitComponents(query) {`
- [coordinateParser.js:79]: `const text = String(query).trim();`
- [coordinateParser.test.mjs:100]: `for (const query of [`
- [coordinateParser.test.mjs:157]: `parseCoordinateQuery(query),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/search/...`
