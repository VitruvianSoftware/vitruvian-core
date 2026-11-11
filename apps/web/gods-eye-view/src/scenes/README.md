# Scenes

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/scenes`.

## Interface
- `[cameraMotion.js:createCameraMotion]`
- `[director.js:SceneDirector]`
- `[interactions.js:createSceneInteractions]`
- `[nepalEvidencePack.js:expandNepalEvidencePack]`
- `[playbackAdapter.js:createScenePlaybackAdapter]`
- `[project.js:PROJECT_VERSION]`
- `[project.js:DEFAULT_SHOT_DURATION_SEC]`
- `[project.js:DEFAULT_HOLD_SEC]`
- `[project.js:uid]`
- `[project.js:deepClone]`
- `[project.js:normalizeLayerEntry]`
- `[project.js:recipeToScene]`
- `[project.js:createDefaultProject]`
- `[project.js:normalizeShot]`
- `[project.js:normalizeProject]`
- `[recipes.js:SCENE_RECIPES]`
- `[recipes.js:SCENE_APPEND_RECIPES]`
- `[recipes.js:getSceneAppendRecipeById]`
- `[recipes.js:displaySceneTitle]`
- `[recipes.js:displayShotTitle]`
- Subdirectory: [dataPacks](./dataPacks/README.md)
- Subdirectory: [packs](./packs/README.md)

## Invariants
- [bootstrapTitleProvenance.test.mjs:24]: `import assert from 'node:assert/strict';`
- [bootstrapTitleProvenance.test.mjs:30]: `assert.ok(scene, 'built-in bootstrap scene exists');`
- [bootstrapTitleProvenance.test.mjs:40]: `assert.equal(shown, title, `${locale}: got ${shown}`);`
- [cameraMotion.test.mjs:24]: `import assert from 'node:assert/strict';`
- [cameraMotion.test.mjs:65]: `assert.deepEqual(h.poses[0], move.from);`
- [cameraMotion.test.mjs:67]: `assert.equal(h.poses.at(-1).alt, 150);`
- [director.test.mjs:37]: `// the visual commit. Several of these assert exactly that plumbing.`
- [director.test.mjs:38]: `import assert from 'node:assert/strict';`
- [director.test.mjs:135]: `assert.equal(director._effectiveShotHoldSec(scene, shot), 7.65);`
- [directorStorageNotices.test.mjs:28]: `import assert from 'node:assert/strict';`

## Side Effects
- [scenePolicy.test.mjs:48]: `for (const entry of fs.readdirSync(dataDir)) {`
- [sceneSaveError.js:48]: `const limit = TEXT_LIMIT.exec(reason);`
- [sceneSaveError.js:51]: `const scene = SCENE_TITLE.exec(path);`
- [sceneSaveError.js:57]: `const shot = SHOT_TITLE.exec(path);`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/scenes/...`
