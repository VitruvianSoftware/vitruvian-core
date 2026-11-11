# Sources

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/sources`.

## Interface
- `[adsbFields.js:readAdsbVerticalRateFpm]`
- `[adsbRecords.js:LOCAL_ADSB_POSITION_STALE_MS]`
- `[adsbRecords.js:LOCAL_ADSB_MESSAGE_STALE_MS]`
- `[adsbRecords.js:LOCAL_ADSB_REFERENCE_MAX_AGE_MS]`
- `[adsbRecords.js:LOCAL_ADSB_POSITION_MARGIN_M]`
- `[adsbRecords.js:LOCAL_ADSB_REANCHOR_AFTER]`
- `[adsbRecords.js:normalizeAdsbCategory]`
- `[adsbRecords.js:localAdsbSpeedLimitKt]`
- `[adsbRecords.js:localAdsbFixIsPlausible]`
- `[adsbRecords.js:recordFromDecoderTrack]`
- `[adsbRecords.js:normalizeDump1090Aircraft]`
- `[adsbRecords.js:localAdsbRecordIsLive]`
- `[adsbRecords.js:localAdsbPositionIsFresh]`
- `[adsbRecords.js:summarizeLocalAdsb]`
- `[adsbRecords.js:localAdsbRecordIsNewer]`
- `[adsbRecords.js:mergeLocalAdsbRecords]`
- `[capability.js:isUnavailableCapability]`
- `[capability.js:sourceResponseError]`
- `[cctvTypes.js:normalizeFeedType]`
- `[cctvTypes.js:isVideoFeedType]`
- Subdirectory: [live](./live/README.md)

## Invariants
- [adsbFields.test.mjs:23]: `import assert from 'node:assert/strict';`
- [adsbFields.test.mjs:28]: `assert.equal(`
- [adsbFields.test.mjs:32]: `assert.equal(readAdsbVerticalRateFpm({ baro_rate: 0, geom_rate: 600 }), 0);`
- [adsbRecords.test.mjs:24]: `import assert from 'node:assert/strict';`
- [adsbRecords.test.mjs:54]: `assert.equal(records.length, 4);`
- [adsbRecords.test.mjs:57]: `assert.deepEqual(byIcao.get('ae5d8a'), {`
- [featureGeometry.test.mjs:23]: `import assert from 'node:assert/strict';`
- [featureGeometry.test.mjs:30]: `assert.ok(across > 150_000 && across < 200_000, String(across));`
- [featureGeometry.test.mjs:31]: `assert.equal(`
- [gbfsStations.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [eventPacks.js:28]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [httpBody.js:33]: `* Read a fetch() Response body as text with a hard byte cap. Rejects early on an`
- [httpBody.js:78]: `/** Parse a fetch() JSON response only after enforcing a hard byte cap. */`
- [httpBody.js:84]: `* Read a fetch() Response body as bytes with the same hard cap as`
- [infrastructureData.js:60]: `* (analyst query engine seam). Pure — no Cesium types. Missing/unknown`
- [infrastructureData.js:155]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [infrastructureData.js:165]: `if (!response.ok) throw new Error(`HTTP ${response.status}`);`
- [nominatim.js:67]: `fetchImpl = (...args) => fetch(...args),`
- [nominatim.js:72]: `throw new TypeError('A query-free Nominatim endpoint is required');`
- [nominatim.js:73]: `const url = new URL(endpoint, 'http://localhost');`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/sources/...`
