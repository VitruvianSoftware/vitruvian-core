# Sky

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/sky`.

## Interface
- `[starrySky.js:STARRY_SKY_CESIUM_VERSION]`
- `[starrySky.js:MILKY_WAY_INTENSITY]`
- `[starrySky.js:SKY_ROTATION_EPSILON_SECONDS]`
- `[starrySky.js:computeSkyRotation]`
- `[starrySky.js:isSkyRotationCurrent]`
- `[starrySky.js:StarrySky]`
- `[stars.js:STAR_LIMIT_MAGNITUDE]`
- `[stars.js:STAR_MIN_SIGMA_PX]`
- `[stars.js:STAR_MAX_SIGMA_PX]`
- `[stars.js:STAR_MIN_ALPHA]`
- `[stars.js:STAR_VERTEX_FLOATS]`
- `[stars.js:raDecToUnitVector]`
- `[stars.js:starBrightness]`
- `[stars.js:starAppearance]`
- `[stars.js:bvToTemperature]`
- `[stars.js:bvToRgb]`
- `[stars.js:buildStarVertices]`

## Invariants
- [starrySky.test.mjs:24]: `import assert from 'node:assert/strict';`
- [starrySky.test.mjs:36]: `assert.ok(Math.abs(actual - expected) <= epsilon, `${actual} vs ${expected}`);`
- [starrySky.test.mjs:39]: `assert.equal(`
- [stars.test.mjs:24]: `import assert from 'node:assert/strict';`
- [stars.test.mjs:41]: `assert.ok(`
- [stars.test.mjs:73]: `assert.deepEqual(previous, {`

## Side Effects
- [starrySky.js:265]: `/** Fetch Cesium's IAU 2006 tables around `time` once per span. */`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/sky/...`
