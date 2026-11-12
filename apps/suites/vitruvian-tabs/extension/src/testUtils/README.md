# Testutils

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/extension/src/testUtils`.

## Interface
- `[jsdomLocation.ts:setWindowUrl]`
- `[jsdomLocation.ts:mockLocationReload]`
- `[jsdomLocation.ts:restoreLocationReload]`
- `[webLocks.d.ts:WebLocksMock]`
- `[webLocks.d.ts:createWebLocksMock]`

## Invariants
- [jsdomLocation.ts:77]: `* "Not implemented: navigation"). Assert on the returned mock; reading`

## Side Effects
- [jsdomLocation.ts:44]: `* http(s) documents may rewrite their query string (for other schemes, e.g.`
- [jsdomLocation.ts:45]: `* chrome-extension://, even query changes throw SecurityError). URLs passed`
- [jsdomLocation.ts:46]: `* here must therefore stay on the jest default http://localhost origin.`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/extension/src/testUtils/...`
