# Src

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src`.

## Interface
- `[awarenessEcho.js:setAwarenessEchoField]`
- `[awarenessEcho.js:clearAwarenessEchoField]`
- `[awarenessEcho.js:getAwarenessEchoField]`
- `[awarenessEcho.js:awarenessEchoActive]`
- `[awarenessEcho.js:awarenessEchoStrength]`
- `[awarenessEcho.js:awarenessEchoAt]`
- `[awarenessEcho.js:awarenessEchoBracket]`
- `[awarenessEcho.js:awarenessEchoColor]`
- `[bloom.js:BLOOM_SCALE_VERSION]`
- `[bloom.js:BLOOM_INTENSITY_MAX]`
- `[bloom.js:BLOOM_INTENSITY_DEFAULT]`
- `[bloom.js:clampBloomIntensity]`
- `[bloom.js:legacyBloomToV2]`
- `[bloom.js:decodeBloomIntensity]`
- `[bloom.js:bloomStrengthFromIntensity]`
- `[camera.js:HOME_VIEW]`
- `[camera.js:flyToHome]`
- `[cameraGroundGuard.js:MIN_EYE_CLEARANCE_M]`
- `[cameraGroundGuard.js:groundClearanceDeficitM]`
- `[cameraGroundGuard.js:guardCameraAboveGround]`
- Subdirectory: [agent](./agent/README.md)
- Subdirectory: [annotations](./annotations/README.md)
- Subdirectory: [app](./app/README.md)
- Subdirectory: [data](./data/README.md)
- Subdirectory: [director](./director/README.md)
- Subdirectory: [i18n](./i18n/README.md)
- Subdirectory: [layers](./layers/README.md)
- Subdirectory: [maps](./maps/README.md)
- Subdirectory: [overlays](./overlays/README.md)
- Subdirectory: [scenes](./scenes/README.md)
- Subdirectory: [sdr](./sdr/README.md)
- Subdirectory: [search](./search/README.md)
- Subdirectory: [services](./services/README.md)
- Subdirectory: [share](./share/README.md)
- Subdirectory: [sky](./sky/README.md)
- Subdirectory: [sources](./sources/README.md)
- Subdirectory: [standalone](./standalone/README.md)
- Subdirectory: [styles](./styles/README.md)
- Subdirectory: [testSupport](./testSupport/README.md)
- Subdirectory: [time](./time/README.md)
- Subdirectory: [tooling](./tooling/README.md)
- Subdirectory: [tools](./tools/README.md)
- Subdirectory: [ui](./ui/README.md)
- Subdirectory: [view](./view/README.md)
- Subdirectory: [voice](./voice/README.md)

## Invariants
- [awarenessEcho.test.mjs:26]: `import assert from 'node:assert/strict';`
- [awarenessEcho.test.mjs:51]: `assert.ok(Math.abs(strength(t0, d) - 1) < 1e-6);`
- [awarenessEcho.test.mjs:52]: `assert.ok(Math.abs(strength(t0 + echo.fadeMs / 2, d) - 0.25) < 1e-6);`
- [browserModuleBoundary.test.mjs:24]: `import assert from 'node:assert/strict';`
- [browserModuleBoundary.test.mjs:57]: `assert.deepEqual(offenders, [], `Node core imports reached the browser build:...`
- [camera.test.mjs:31]: `import assert from 'node:assert/strict';`
- [camera.test.mjs:60]: `assert.equal(HOME_VIEW.name, 'Irvine, CA');`
- [camera.test.mjs:62]: `assert.ok(HOME_VIEW.latitude > 33.6 && HOME_VIEW.latitude < 33.76, `lat ${HOM...`
- [cameraGlobeRotation.test.mjs:25]: `import assert from 'node:assert/strict';`
- [cameraGlobeRotation.test.mjs:56]: `assert.ok(`

## Side Effects
- [awarenessEcho.js:36]: `*   may move it in place; it is read on every query.`
- [cameraHandoff.test.mjs:38]: `const voice = fs.readFileSync(path.join(ROOT, 'src', 'voice', 'gevActions.js'...`
- [cameraHandoff.test.mjs:39]: `const cameraVerbs = fs.readFileSync(path.join(ROOT, 'src', 'cameraVerbs.js'),...`
- [cameraHandoff.test.mjs:40]: `const cockpitTracking = fs.readFileSync(path.join(ROOT, 'src', 'cockpitTracki...`
- [celestialRingView.test.mjs:182]: `// Fixed sun and moon directions; Cesium's own model would fetch its`
- [cockpitMarkup.test.mjs:78]: `fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8'),`
- [cockpitMarkup.test.mjs:82]: `const sceneDirector = fs.readFileSync(`
- [cockpitMarkup.test.mjs:86]: `const manager = fs.readFileSync(`
- [codexOauthRealtime.test.mjs:198]: `https_proxy: 'http://proxy.fixture:8080',`
- [codexOauthRealtime.test.mjs:205]: `queueMicrotask(() => child.emit('spawn'));`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/...`
