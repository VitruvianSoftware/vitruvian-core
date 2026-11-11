# Director

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/director`.

## Interface
- `[authoring.js:editSceneDetails]`
- `[authoring.js:selectSceneDocument]`
- `[camera.js:resolveCameraPose]`
- `[camera.js:resolveCameraMove]`
- `[camera.js:normalizeCameraLongitude]`
- `[camera.js:sampleCameraMove]`
- `[cameraDocument.js:validateSceneCameras]`
- `[clock.js:createPlaybackClock]`
- `[document.js:SCENE_DOCUMENT_VERSION]`
- `[document.js:validateSceneDocument]`
- `[document.js:parseSceneDocument]`
- `[document.js:stringifySceneDocument]`
- `[documentFields.js:SCENE_DOCUMENT_LIMITS]`
- `[documentFields.js:SceneDocumentError]`
- `[documentFields.js:fail]`
- `[documentFields.js:object]`
- `[documentFields.js:fields]`
- `[documentFields.js:string]`
- `[documentFields.js:number]`
- `[documentFields.js:optional]`
- Subdirectory: [interactions](./interactions/README.md)
- Subdirectory: [packs](./packs/README.md)
- Subdirectory: [sharing](./sharing/README.md)

## Invariants
- [camera.test.mjs:24]: `import assert from 'node:assert/strict';`
- [camera.test.mjs:73]: `assert.deepEqual(project.scenes[0].anchors, raw.scenes[0].anchors);`
- [camera.test.mjs:74]: `assert.deepEqual(`
- [clock.test.mjs:24]: `import assert from 'node:assert/strict';`
- [clock.test.mjs:73]: `assert.equal(f.clock.snapshot.sceneElapsedSec, 2);`
- [clock.test.mjs:76]: `assert.equal(f.clock.activeTimers, 0);`
- [director-dateline-seek.test.mjs:24]: `import assert from 'node:assert/strict';`
- [director-dateline-seek.test.mjs:39]: `assert.equal(`
- [director-dateline-seek.test.mjs:43]: `assert.equal(cameraAtProgress(camera(a), camera(b), 0).lon, a);`
- [document.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/director/...`
