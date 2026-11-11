# Aircraft

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/aircraft`.

## Interface
- `[classification.js:createMilitaryRegistry]`

## Invariants
- [classification.test.mjs:24]: `import assert from 'node:assert/strict';`
- [classification.test.mjs:42]: `assert.equal(first.isMilitaryIcao('abc123'), true);`
- [classification.test.mjs:43]: `assert.equal(second.isMilitaryIcao('abc123'), false);`

## Side Effects
- [classification.js:36]: `/** @type {boolean} A self-poll fetch is in flight. */`
- [classification.test.mjs:85]: `getSnapshot(query, { signal }) {`
- [classification.test.mjs:97]: `getSnapshot(query, { signal }) {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/aircraft/...`
