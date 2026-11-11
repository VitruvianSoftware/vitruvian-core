# Sharing

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/director/sharing`.

## Interface
- `[bundle.js:BUNDLE_SOURCE]`
- `[bundle.js:SHARE_LIMITS]`
- `[bundle.js:parseSceneShare]`
- `[bundle.js:readSceneShare]`
- `[bundle.js:createSceneBundle]`
- `[bundle.js:createBundleAssets]`
- `[lifetime.js:withShareSignal]`
- `[preview.js:describeSceneShare]`

## Invariants
- [sharing.test.mjs:24]: `import assert from 'node:assert/strict';`
- [sharing.test.mjs:90]: `assert.equal(reads, 1);`
- [sharing.test.mjs:91]: `assert.equal(JSON.stringify(original), before);`

## Side Effects
- [bundle.js:155]: `/** Export only explicitly supplied pack bytes; never fetch external assets o...`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/director/sharing/...`
