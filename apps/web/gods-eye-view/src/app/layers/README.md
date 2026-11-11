# Layers

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/app/layers`.

## Interface
- `[airQuality.js:createApplicationAirQuality]`
- `[aisLiveVessels.js:createApplicationVessels]`
- `[alprCameras.js:createApplicationAlpr]`
- `[bikeshare.js:createApplicationBikeshare]`
- `[cctv.js:createApplicationCctv]`
- `[cyclones.js:createApplicationCyclones]`
- `[directions.js:createApplicationDirections]`
- `[droneAirspace.js:createApplicationDroneAirspace]`
- `[earthquakes.js:createApplicationEarthquakes]`
- `[firms.js:firmsServices]`
- `[firms.js:createApplicationFirms]`
- `[flights.js:createApplicationFlights]`
- `[ghostMaps.js:createApplicationGhostMaps]`
- `[gnss.js:createApplicationGnssIntegrity]`
- `[localAdsb.js:createApplicationLocalAdsb]`
- `[militaryAwareness.js:createApplicationAwareness]`
- `[militaryFlights.js:createApplicationMilitary]`
- `[militaryInstallations.js:createApplicationInstallations]`
- `[osmPlaces.js:createApplicationOsmPlaces]`
- `[overlayHost.js:overlayHost]`

## Invariants
- [streetLevel.test.mjs:23]: `import assert from 'node:assert/strict';`
- [streetLevel.test.mjs:38]: `assert.deepEqual(layer.providerIds, ['example']);`
- [streetLevel.test.mjs:39]: `assert.deepEqual(`
- [transit.test.mjs:24]: `import assert from 'node:assert/strict';`
- [transit.test.mjs:55]: `assert.equal(height.requestHeight(lat, lon).height, null);`
- [transit.test.mjs:60]: `assert.equal(`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/app/layers/...`
