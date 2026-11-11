# Droneairspace

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/droneAirspace`.

## Interface
- `[cards.js:DRONE_AIRSPACE_OVERLAY_SOURCE_ID]`
- `[cards.js:droneAirspaceAccent]`
- `[cards.js:droneAirspaceAnchorDegrees]`
- `[cards.js:buildDroneAirspaceCard]`
- `[index.js:droneAirspaceColor]`
- `[index.js:createDroneAirspaceLayer]`
- `[records.js:droneAirspaceAltitude]`
- `[records.js:droneAirspaceTypeLabel]`
- `[records.js:normalizeDroneAirspaceSnapshot]`
- `[source.js:createDroneAirspaceSource]`

## Invariants
- [cards.test.mjs:24]: `import assert from 'node:assert/strict';`
- [cards.test.mjs:47]: `assert.ok(Math.abs(anchor.lon - -77.1) < 1e-9);`
- [cards.test.mjs:48]: `assert.ok(Math.abs(anchor.lat - 38.9) < 1e-9);`
- [docs.test.mjs:24]: `import assert from 'node:assert/strict';`
- [docs.test.mjs:42]: `assert.ok(token, 'drone-airspace has a reserved token');`
- [docs.test.mjs:43]: `assert.match(section, new RegExp(`share-link token \`${token}\``));`
- [ownership.test.mjs:23]: `import assert from 'node:assert/strict';`
- [ownership.test.mjs:108]: `assert.equal(await h.layer.update(h.viewer), true);`
- [ownership.test.mjs:110]: `assert.equal(entities.length, 3);`
- [records.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [index.js:230]: `// A stale snapshot is as old as its fetch, not this poll.`
- [index.js:306]: `console.warn('[Data:DroneAirspace] Fetch error:', e);`
- [ownership.test.mjs:186]: `test('a stale snapshot reads STALE, dated by its own fetch, and a fresh one c...`
- [ownership.test.mjs:209]: `if (fail) throw new Error('FAA SUA HTTP 502');`
- [ownership.test.mjs:218]: `assert.equal(h.layer.getStats().error, 'FAA SUA HTTP 502');`
- [source.js:27]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:37]: `if (!response.ok) throw new Error(`FAA SUA HTTP ${response.status}`);`
- [source.test.mjs:110]: `test('an upstream failure surfaces its HTTP status', async () => {`
- [source.test.mjs:114]: `await assert.rejects(source.getSnapshot(), /FAA SUA HTTP 503/);`
- [source.test.mjs:129]: `test('the snapshot detail carries the proxy staleness and fetch time', async ...`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/droneAirspace/...`
