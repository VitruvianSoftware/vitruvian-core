# Interactions

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/director/interactions`.

## Interface
- `[document.js:validateSceneInteractions]`
- `[session.js:createInteractionSession]`

## Invariants
- [interactions.test.mjs:24]: `import assert from 'node:assert/strict';`
- [interactions.test.mjs:102]: `assert.deepEqual(`
- [interactions.test.mjs:147]: `assert.throws(() => parseSceneDocument(JSON.stringify(p)));`

## Side Effects
- [document.js:91]: `'expected HTTPS source URL without credentials, query or fragment',`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/director/interactions/...`
