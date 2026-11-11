# Panels

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui/views/panels`.

## Interface
- Internal implementation components

## Invariants
- [DrawMarkList.test.mjs:29]: `import assert from 'node:assert/strict';`
- [DrawMarkList.test.mjs:74]: `assert.equal(list.classList.contains('visible'), false);`
- [DrawMarkList.test.mjs:76]: `assert.equal(list.classList.contains('visible'), true);`
- [GeoImport.test.mjs:28]: `import assert from 'node:assert/strict';`
- [GeoImport.test.mjs:81]: `assert.equal(picker.getAttribute('accept'), GEO_FILE_ACCEPT);`
- [GeoImport.test.mjs:85]: `assert.equal(opened, 0, 'not before the file import presents itself');`
- [WorldTimeline.test.mjs:27]: `import assert from 'node:assert/strict';`
- [WorldTimeline.test.mjs:70]: `assert.ok(bar(), 'shown while live');`
- [WorldTimeline.test.mjs:72]: `assert.equal(live.disabled, true, 'already live');`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/views/panels/...`
