# Queries

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/tools/queries`.

## Interface
- `[atmosphere.js:weatherWindow]`
- `[atmosphere.js:getWeatherMap]`
- `[atmosphere.js:getWind]`
- `[aviation.js:airlineDesignator]`
- `[aviation.js:aircraftInArea]`
- `[aviation.js:findAircraft]`
- `[aviation.js:getAircraftTrack]`
- `[aviation.js:getAircraftInfo]`
- `[brief.js:situationBrief]`
- `[brief.js:getHudCaption]`
- `[brief.js:militaryAwareness]`
- `[cables.js:findSubmarineCables]`
- `[environment.js:getWeather]`
- `[environment.js:getRegionalBrief]`
- `[environment.js:getCyclones]`
- `[environment.js:getFirePerimeters]`
- `[environment.js:getTerrainHeight]`
- `[environment.js:findMilitaryInstallations]`
- `[environment.js:getMapFeatures]`
- `[events.js:getBhoteKoshiFlood]`

## Invariants
- [atmosphere.test.mjs:23]: `import assert from 'node:assert/strict';`
- [atmosphere.test.mjs:64]: `assert.deepEqual(austin, {`
- [atmosphere.test.mjs:80]: `assert.equal(edge.west, -130);`
- [aviation.test.mjs:23]: `import assert from 'node:assert/strict';`
- [aviation.test.mjs:100]: `assert.equal(result.summary, '2 aircraft in 60 km around 37.600, -122.300.');`
- [aviation.test.mjs:101]: `assert.deepEqual(`
- [cables.test.mjs:23]: `import assert from 'node:assert/strict';`
- [cables.test.mjs:80]: `assert.equal(`
- [cables.test.mjs:84]: `assert.deepEqual(virginia.data.rows, [{ id: 'marea', name: 'MAREA' }]);`
- [environment.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [aviation.js:80]: `const match = /^([A-Z]{3})\d[0-9A-Z]{0,3}$/.exec(text);`
- [aviation.test.mjs:65]: `async getSnapshot(query) {`
- [aviation.test.mjs:66]: `calls.push(query);`
- [aviation.test.mjs:259]: `throw new LiveSourceError('unavailable', `OpenSky HTTP ${status}`, {`
- [brief.js:136]: `* direct query does (place lookups are cached).`
- [cables.js:68]: `const { cables, landingPoints } = await services.cables.fetch(signal);`
- [cables.test.mjs:30]: `async fetch() {`
- [cables.test.mjs:122]: `async fetch() {`
- [cables.test.mjs:167]: `test('the local fetch serves bundled data files and nothing outside them', as...`
- [infrastructure.test.mjs:146]: `test('the bundled datasets load through the local fetch', async () => {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/tools/queries/...`
