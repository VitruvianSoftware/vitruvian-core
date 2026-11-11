# Live

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/sources/live`.

## Interface
- `[aircraft.js:normalizeOpenSkyAircraft]`
- `[aircraft.js:normalizeReadsbAircraft]`
- `[aircraft.js:openSkySnapshot]`
- `[aircraft.js:readsbSnapshot]`
- `[aircraft.js:normalizeAircraftTrack]`
- `[aircraft.js:readsbIdentities]`
- `[contract.js:LiveSourceError]`
- `[contract.js:finite]`
- `[contract.js:epoch]`
- `[contract.js:cleanText]`
- `[contract.js:coordinates]`
- `[contract.js:admitRecords]`
- `[contract.js:readResponse]`
- `[contract.js:httpError]`
- `[standalone.js:createFlightSource]`
- `[standalone.js:createMilitarySource]`
- `[standalone.js:createVesselSource]`
- `[vessels.js:normalizeVesselObservation]`
- `[vessels.js:vesselSnapshot]`
- `[vessels.js:normalizeVesselTrack]`

## Invariants
- [contract.test.mjs:24]: `import assert from 'node:assert/strict';`
- [contract.test.mjs:61]: `assert.equal(row.id, 'abc123');`
- [contract.test.mjs:62]: `assert.equal(row.baroAltitudeM, 1000);`

## Side Effects
- [contract.js:29]: `* Sources expose getSnapshot(query, { signal }) and optionally`
- [contract.js:157]: `status === 429 ? `${source} rate limited` : `${source} HTTP ${status}`,`
- [contract.test.mjs:131]: `// live adsb.lol /v2/mil fetch had 82 such rows of 239.`
- [contract.test.mjs:193]: `// GNSS; 26 of 157 positioned rows in a live /v2/mil fetch had only that.`
- [contract.test.mjs:233]: `test('construction is inert; adapters preserve routes, viewport query, cache ...`
- [standalone.js:37]: `const defaultFetch = (...args) => globalThis.fetch(...args);`
- [standalone.js:90]: `async getSnapshot(query = {}, { signal } = {}) {`
- [standalone.js:92]: `if (Number.isFinite(query.latitude) && Number.isFinite(query.longitude)) {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/sources/live/...`
