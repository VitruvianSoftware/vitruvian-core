# Providers

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers`.

## Interface
- `[acartia.js:acartiaRetryCooldownMs]`
- `[acartia.js:acartiaProxy]`
- `[cctv.js:cctvProxy]`
- `[cyclones.js:parseCycloneStatus]`
- `[cyclones.js:attachCycloneGeometry]`
- `[cyclones.js:cycloneProxy]`
- `[droneAirspace.js:droneAirspaceProxy]`
- `[firePerimeters.js:firePerimetersProxy]`
- `[firms.js:describeFetchError]`
- `[firms.js:isAddressSelectionFailure]`
- `[firms.js:fetchIpv4]`
- `[firms.js:fetchFirms]`
- `[firms.js:firmsProxy]`
- `[gbfs.js:GBFS_CLIENT_IDENTIFIER]`
- `[gbfs.js:GBFS_MAX_BODY_BYTES]`
- `[gbfs.js:GBFS_RATE_PER_MIN]`
- `[gbfs.js:fetchGbfsUpstream]`
- `[gbfs.js:gbfsProxy]`
- `[ghostMaps.js:ghostMapsPollMs]`
- `[ghostMaps.js:createGhostMapsWatcher]`
- Subdirectory: [aircraft](./aircraft/README.md)
- Subdirectory: [cctv](./cctv/README.md)
- Subdirectory: [common](./common/README.md)
- Subdirectory: [gemini](./gemini/README.md)
- Subdirectory: [inaturalist](./inaturalist/README.md)
- Subdirectory: [mapillary](./mapillary/README.md)
- Subdirectory: [military-installations](./military-installations/README.md)
- Subdirectory: [openai](./openai/README.md)
- Subdirectory: [overpass](./overpass/README.md)
- Subdirectory: [places](./places/README.md)
- Subdirectory: [radio](./radio/README.md)
- Subdirectory: [regional](./regional/README.md)
- Subdirectory: [space](./space/README.md)
- Subdirectory: [vessels](./vessels/README.md)
- Subdirectory: [wind](./wind/README.md)

## Invariants
- [acartia.test.mjs:24]: `import assert from 'node:assert/strict';`
- [acartia.test.mjs:45]: `assert.equal(plugin.name, 'acartia');`
- [acartia.test.mjs:46]: `assert.equal(typeof plugin.configureServer, 'function');`
- [ghostMaps.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ghostMaps.test.mjs:113]: `assert.equal(await watcher.checkNow(), true);`
- [ghostMaps.test.mjs:116]: `assert.equal(first.commit, sha('1'));`
- [local-receivers.js:172]: `* Resolve a feed host name and require every address to be local.`
- [transitHistory.test.mjs:24]: `import assert from 'node:assert/strict';`
- [transitHistory.test.mjs:54]: `assert.equal(h.get('mbta', 'bus', 500000).fixes.length, 1);`
- [transitHistory.test.mjs:55]: `assert.equal(h.get('mbta', 'bus', 999999).fixes.length, 1);`

## Side Effects
- [acartia.js:24]: `import { coalesceProxyRequest, readResponseJsonCapped } from './common/http.js';`
- [acartia.js:58]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [acartia.test.mjs:172]: `'sec-fetch-site': 'cross-site',`
- [acartia.test.mjs:193]: `'sec-fetch-site': 'same-origin',`
- [cctv.js:77]: `/** Retry a failed fetch sooner than a full refresh window, never under a min...`
- [cctv.js:132]: `* Fetch a frame from a provider with a per-camera refresh floor. Inside the`
- [cctv.js:136]: `* fetch backs off for a minute (capped at the floor) instead of a full`
- [cyclones.js:23]: `import { readResponseTextCapped } from './common/http.js';`
- [cyclones.js:284]: `fetchImpl = fetch,`
- [cyclones.js:320]: `const url = new URL(`${GIS}/${spec.id}/query`);`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/...`
