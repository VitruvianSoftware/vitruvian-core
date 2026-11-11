# Views

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui/views`.

## Interface
- `[index.js:APPLICATION_VIEWS]`
- `[index.js:mountApplicationViews]`
- Subdirectory: [panels](./panels/README.md)

## Invariants
- [intelHudView.test.mjs:31]: `import assert from 'node:assert/strict';`
- [intelHudView.test.mjs:100]: `assert.equal(root.querySelectorAll('.hud-corner').length, 4);`
- [intelHudView.test.mjs:101]: `assert.equal(root.querySelectorAll('.hud-edge').length, 2);`
- [mountApplicationViews.test.mjs:27]: `import assert from 'node:assert/strict';`
- [mountApplicationViews.test.mjs:49]: `assert.deepEqual(hostNames(), ['welcome']);`
- [mountApplicationViews.test.mjs:50]: `assert.equal(document.getElementById('key-setup-chip'), null);`

## Side Effects
- [intelHudView.test.mjs:98]: `// The panel layout controllers query these synchronously at registration.`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/views/...`
