# Launches

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/launches`.

## Interface
- `[camera.js:createCamera]`
- `[controls.js:createControls]`
- `[index.js:createRocketLaunchesLayer]`
- `[ingestion.js:createIngestion]`
- `[launchPad.js:createLaunchPad]`
- `[lifecycle.js:createLaunchHover]`
- `[lifecycle.js:createLifecycle]`
- `[model.js:UNKNOWN_LAUNCH_STATUS]`
- `[model.js:createModel]`
- `[orbitRendering.js:createOrbitRendering]`
- `[overlays.js:createOverlays]`
- `[panel.js:createPanel]`
- `[paths.js:createPaths]`
- `[policy.js:WINDOW_DAYS]`
- `[policy.js:ROCKET_MISSION_AMBIENT_OVERLAY_SOURCE_ID]`
- `[policy.js:ROCKET_MISSION_SELECTED_OVERLAY_SOURCE_ID]`
- `[policy.js:ROCKET_MISSION_AMBIENT_OVERLAY_COHORT_LIMIT]`
- `[policy.js:ROCKET_MISSION_AMBIENT_OVERLAY_COLLISION_CAPACITY]`
- `[policy.js:ROCKET_MISSION_SELECTED_OVERLAY_SOURCE_OPTIONS]`
- `[policy.js:ROCKET_MISSION_AMBIENT_OVERLAY_SOURCE_OPTIONS]`

## Invariants
- [failedEntry.test.mjs:26]: `import assert from 'node:assert/strict';`
- [failedEntry.test.mjs:290]: `assert.equal(entered, false, 'a failed mission index fails the enable');`
- [failedEntry.test.mjs:291]: `assert.deepEqual(f.enabledIds(), ['earthquakes']);`
- [hover.test.mjs:24]: `import assert from 'node:assert/strict';`
- [hover.test.mjs:95]: `assert.equal(rig.cursor(), 'pointer');`
- [hover.test.mjs:101]: `assert.equal(rig.picks(), 1);`
- [ingestion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ingestion.test.mjs:54]: `assert.equal(req.url, '/api/launches');`
- [ingestion.test.mjs:72]: `assert.ok(['/api/launches', '/api/celestrak/active'].includes(url));`
- [missionStatus.i18n.test.mjs:25]: `import assert from 'node:assert/strict';`

## Side Effects
- [controls.js:47]: `* query engine. On demand only (once per spoken query); [] while the`
- [failedEntry.test.mjs:282]: `test(`a ${path} Space Missions entry that gets HTTP 429 rolls back instead of...`
- [failedEntry.test.mjs:294]: `assert.equal(f.missions.getStats().error, 'HTTP 429');`
- [failedEntry.test.mjs:451]: `assert.equal(f.missions.getStats().error, 'HTTP 429');`
- [ingestion.js:255]: `console.warn('[Data:RocketLaunches] Fetch error:', error);`
- [ingestion.test.mjs:25]: `import http from 'node:http';`
- [ingestion.test.mjs:49]: `const server = http.createServer((req, res) => {`
- [ingestion.test.mjs:69]: `const origin = `http://127.0.0.1:${server.address().port}`;`
- [source.js:29]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [source.js:35]: `if (!response.ok) throw new Error(`HTTP ${response.status}`);`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/launches/...`
