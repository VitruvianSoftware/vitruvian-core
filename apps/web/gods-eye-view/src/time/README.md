# Time

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/time`.

## Interface
- `[julian.js:julianAt]`
- `[viewerClock.js:followWorldTime]`
- `[worldClock.js:isWorldTime]`
- `[worldClock.js:WORLD_CLOCK_TICK_MS]`
- `[worldClock.js:createWorldClock]`
- `[worldClock.js:worldClock]`
- `[worldClock.js:worldTimeFor]`

## Invariants
- [worldClock.test.mjs:24]: `import assert from 'node:assert/strict';`
- [worldClock.test.mjs:54]: `assert.equal(clock.isLive(), true);`
- [worldClock.test.mjs:55]: `assert.equal(clock.now(), t.wall);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/time/...`
