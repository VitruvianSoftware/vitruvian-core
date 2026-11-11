# Google

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/streetLevel/providers/google`.

## Interface
- `[index.js:createGoogleProvider]`
- `[mapsLoader.js:createMapsLoader]`
- `[policy.js:GOOGLE_PROVIDER_ID]`
- `[policy.js:GOOGLE_NAME]`
- `[policy.js:GOOGLE_LABEL]`
- `[policy.js:GOOGLE_KEY_ID]`
- `[policy.js:PICK_PREFIX]`
- `[policy.js:COLORS]`
- `[policy.js:GOOGLE_CREDIT_HTML]`
- `[policy.js:KEY_REJECTED_MESSAGE]`
- `[policy.js:NEAREST_TIMEOUT_MS]`
- `[policy.js:OPEN_TIMEOUT_MS]`
- `[policy.js:DETAILS_TIMEOUT_MS]`
- `[policy.js:DETAILS_RETRY_COOLDOWN_MS]`
- `[policy.js:NO_ANSWER_MESSAGE]`
- `[policy.js:GROUND_CLICK_HINT]`
- `[policy.js:streetViewUrl]`
- `[policy.js:imageDateMs]`
- `[policy.js:creatorFrom]`
- `[viewer.js:createGoogleViewer]`

## Invariants
- [mapsLoader.test.mjs:23]: `import assert from 'node:assert/strict';`
- [mapsLoader.test.mjs:62]: `assert.equal(page.scripts.length, 1, 'one script for concurrent imports');`
- [mapsLoader.test.mjs:64]: `assert.equal(`
- [provider.test.mjs:23]: `import assert from 'node:assert/strict';`
- [provider.test.mjs:88]: `assert.equal(def.id, 'google');`
- [provider.test.mjs:89]: `assert.equal(def.label, 'GOOGLE STREET VIEW');`
- [viewer.test.mjs:22]: `import assert from 'node:assert/strict';`
- [viewer.test.mjs:63]: `assert.equal(host.children.length, 1, 'renders in its own element');`
- [viewer.test.mjs:65]: `assert.equal(panorama.options.fullscreenControl, false);`

## Side Effects
- [policy.js:76]: `const match = /^(\d{4})-(\d{2})/.exec(String(imageDate ?? ''));`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/streetLevel/providers/google/...`
