# Ui

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui`.

## Interface
- `[aircraftDisplay.js:AircraftDisplay]`
- `[applicationShell.js:StyleManager]`
- `[applicationShortcuts.js:bindApplicationShortcuts]`
- `[cameraOrientationControls.js:OBLIQUE_PITCH]`
- `[cameraOrientationControls.js:STRAIGHT_DOWN_PITCH]`
- `[cameraOrientationControls.js:pickViewTarget]`
- `[cameraOrientationControls.js:readCameraTargetFrame]`
- `[cameraOrientationControls.js:toggleCameraTilt]`
- `[cameraOrientationControls.js:resetCameraNorth]`
- `[cameraOrientationControls.js:createCameraOrientationAnimator]`
- `[cameraOrientationControls.js:bindCameraOrientationControls]`
- `[cctvBindings.js:_initCctvPanel]`
- `[cctvCalibration.js:_activeCctvCameraId]`
- `[cctvCalibration.js:_resetCctvCalibration]`
- `[cctvCalibration.js:_beginCctvCalValueEdit]`
- `[cctvCalibration.js:presentCctvCalibration]`
- `[cctvControls.js:CctvControls]`
- `[cctvFrames.js:cctvSourceStatusLabel]`
- `[cctvFrames.js:cctvSourceMessageText]`
- `[cctvFrames.js:cctvSourceLabelText]`
- Subdirectory: [kit](./kit/README.md)
- Subdirectory: [layerPanel](./layerPanel/README.md)
- Subdirectory: [rail](./rail/README.md)
- Subdirectory: [stores](./stores/README.md)
- Subdirectory: [styles](./styles/README.md)
- Subdirectory: [views](./views/README.md)

## Invariants
- [awarenessPanel.test.mjs:27]: `import assert from 'node:assert/strict';`
- [awarenessPanel.test.mjs:98]: `assert.equal(`
- [awarenessPanel.test.mjs:103]: `assert.equal(`
- [cameraOrientationControls.test.mjs:23]: `import assert from 'node:assert/strict';`
- [cameraOrientationControls.test.mjs:167]: `assert.ok(frame, `no frame at ${headingDeg}/${pitchDeg}`);`
- [cameraOrientationControls.test.mjs:169]: `assert.ok(`
- [cctvBadges.test.mjs:24]: `import assert from 'node:assert/strict';`
- [cctvBadges.test.mjs:34]: `assert.deepEqual(presentCctvSourceBadge(active, enabled, frame), {`
- [cctvBadges.test.mjs:71]: `assert.deepEqual(quality, {`
- [cctvControls.test.mjs:23]: `import assert from 'node:assert/strict';`

## Side Effects
- [cctvFrames.js:56]: `'Media fetch failed': msg('Media fetch failed'),`
- [cctvFrames.js:89]: `const http = /^Upstream HTTP (\d{3})$/.exec(text);`
- [cctvFrames.js:90]: `if (http) return t('Upstream HTTP {status}', { status: http[1] });`
- [cockpitBriefPages.js:40]: `sourceKey: msg('{source} · LOCATION QUERY · RECENT'),`
- [cockpitBriefing.js:307]: `this.brief.source = t('{source} · LOCATION QUERY', {`
- [cockpitBriefing.test.mjs:115]: `'GOOGLE NEWS RSS · LOCATION QUERY · RECENT',`
- [cockpitBriefing.test.mjs:184]: `assert.equal(text('#cockpit-brief-source'), 'WIRE · LOCATION QUERY');`
- [cockpitBriefing.test.mjs:240]: `assert.equal(text('#cockpit-brief-source'), 'WIRE · LOCATION QUERY');`
- [cockpitOrbitalFocus.test.mjs:255]: `globalThis.matchMedia = (query) => ({`
- [cockpitOrbitalFocus.test.mjs:256]: `matches: query.includes('reduce') && reducedMotion,`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/...`
