# Layers

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers`.

## Interface
- Internal implementation components
- Subdirectory: [airQuality](./airQuality/README.md)
- Subdirectory: [aircraft](./aircraft/README.md)
- Subdirectory: [alpr](./alpr/README.md)
- Subdirectory: [awareness](./awareness/README.md)
- Subdirectory: [bikeshare](./bikeshare/README.md)
- Subdirectory: [cctv](./cctv/README.md)
- Subdirectory: [cyclones](./cyclones/README.md)
- Subdirectory: [directions](./directions/README.md)
- Subdirectory: [droneAirspace](./droneAirspace/README.md)
- Subdirectory: [earthquakes](./earthquakes/README.md)
- Subdirectory: [firms](./firms/README.md)
- Subdirectory: [flights](./flights/README.md)
- Subdirectory: [ghostMaps](./ghostMaps/README.md)
- Subdirectory: [gnss](./gnss/README.md)
- Subdirectory: [installations](./installations/README.md)
- Subdirectory: [launches](./launches/README.md)
- Subdirectory: [localAdsb](./localAdsb/README.md)
- Subdirectory: [military](./military/README.md)
- Subdirectory: [osmPlaces](./osmPlaces/README.md)
- Subdirectory: [perimeters](./perimeters/README.md)
- Subdirectory: [radio](./radio/README.md)
- Subdirectory: [recentImagery](./recentImagery/README.md)
- Subdirectory: [satellites](./satellites/README.md)
- Subdirectory: [streetLevel](./streetLevel/README.md)
- Subdirectory: [submarineCables](./submarineCables/README.md)
- Subdirectory: [traffic](./traffic/README.md)
- Subdirectory: [transit](./transit/README.md)
- Subdirectory: [vessels](./vessels/README.md)
- Subdirectory: [weather](./weather/README.md)
- Subdirectory: [wildlifeSightings](./wildlifeSightings/README.md)
- Subdirectory: [wind](./wind/README.md)

## Invariants
- [feedDegradationI18n.test.mjs:26]: `import assert from 'node:assert/strict';`
- [feedDegradationI18n.test.mjs:51]: `assert.notEqual(shown, english, `status ${payload.status} still English`);`
- [feedDegradationI18n.test.mjs:72]: `assert.notEqual(shown, 'SIMULATED — TomTom daily budget reached');`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/...`
