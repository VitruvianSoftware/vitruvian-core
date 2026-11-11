# View

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/view`.

## Interface
- `[index.js:STYLE_URL_NAMES]`
- `[index.js:VIEW_STYLES]`
- `[index.js:VIEW_MAPS]`
- `[index.js:VIEW_FOLLOW_KINDS]`
- `[index.js:VIEW_ANNOTATION_TYPES]`
- `[index.js:VIEW_PROPERTIES]`
- `[index.js:createView]`
- `[index.js:viewToParams]`
- `[index.js:annotationsFromParams]`
- `[index.js:viewFromParams]`
- `[index.js:viewUrl]`

## Invariants
- [index.test.mjs:23]: `import assert from 'node:assert/strict';`
- [index.test.mjs:48]: `assert.equal(params.get('style'), 'crt');`
- [index.test.mjs:49]: `assert.equal(params.get('map'), 'osm');`

## Side Effects
- [index.test.mjs:97]: `fs.readFile(new URL('../sharelink.js', import.meta.url), 'utf8'),`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/view/...`
