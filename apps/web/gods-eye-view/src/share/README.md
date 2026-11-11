# Share

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/share`.

## Interface
- `[follow.js:SHARE_VIEW_ENTITY_KINDS]`
- `[follow.js:SHARE_VIEW_FOLLOW_OFFSET_DEFAULT]`
- `[follow.js:followOffsetToEnu]`
- `[follow.js:followOffsetFromEnu]`
- `[follow.js:followCameraFor]`
- `[legacyShareState.js:LEGACY_SHARE_STATE_KEYS]`
- `[legacyShareState.js:fromLegacyShareState]`
- `[legacyShareState.js:toLegacyShareState]`
- `[shareLinkPath.js:SHARE_PATH_SEGMENT]`
- `[shareLinkPath.js:parseSharePath]`
- `[shareLinkPath.js:appRootUrl]`
- `[shareLinkPath.js:shareLinkUrl]`
- `[viewCodec.js:SHARE_VIEW_FORMAT_VERSION]`
- `[viewCodec.js:MAX_SHARE_VIEW_CHARS]`
- `[viewCodec.js:SHARE_VIEW_EPOCH_S]`
- `[viewCodec.js:SHARE_VIEW_ENUMS]`
- `[viewCodec.js:SHARE_VIEW_PANELS]`
- `[viewCodec.js:SHARE_VIEW_STYLE_PARAMS]`
- `[viewCodec.js:BY_STYLE]`
- `[viewCodec.js:SHARE_VIEW_FLAGS]`

## Invariants
- [legacyShareState.test.mjs:24]: `import assert from 'node:assert/strict';`
- [legacyShareState.test.mjs:98]: `assert.ok(parsed, `long form parses: ${hash}`);`
- [legacyShareState.test.mjs:102]: `assert.equal(decoded.ok, true, decoded.reason);`
- [shareLinkPath.test.mjs:24]: `import assert from 'node:assert/strict';`
- [shareLinkPath.test.mjs:28]: `assert.deepEqual(parseSharePath('/share/AQc'), {`
- [shareLinkPath.test.mjs:32]: `assert.deepEqual(parseSharePath('/gev/share/AQc/'), {`
- [viewCodec.test.mjs:24]: `import assert from 'node:assert/strict';`
- [viewCodec.test.mjs:90]: `/** Decode and require success, returning the result. */`
- [viewCodec.test.mjs:93]: `assert.equal(result.ok, true, `decode failed: ${result.reason}`);`
- [wire.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [legacyShareState.test.mjs:70]: `location: { hash: body, href: `http://localhost/${body}` },`
- [legacyShareState.test.mjs:232]: `globalThis.window = { location: { hash: '', href: 'http://localhost/' } };`
- [legacyShareState.test.mjs:329]: `globalThis.window = { location: { hash: '', href: 'http://localhost/' } };`
- [shareLinkPath.js:45]: `const match = SHARE_PATH.exec(pathname);`
- [shareLinkPath.js:58]: `* directory of any other page, with no hash. The query is kept.`
- [shareLinkPath.test.mjs:43]: `test('the app root drops a share path and the hash, and keeps the query', () ...`
- [shareLinkPath.test.mjs:49]: `appRootUrl('http://localhost:4173/gev/share/AQc').href,`
- [shareLinkPath.test.mjs:50]: `'http://localhost:4173/gev/',`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/share/...`
