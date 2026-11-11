# Services

## Overview
Component package providing implementation for `apps/suites/tabula/extension/src/services`.

## Interface
- `[api.ts:SaveOptions]`
- `[api.ts:RelayAcceptResult]`
- `[api.ts:ApiService]`
- `[auth.ts:User]`
- `[auth.ts:AuthResponse]`
- `[auth.ts:AuthService]`
- `[cross-window-sync.ts:SyncMessage]`
- `[cross-window-sync.ts:crossWindowSync]`
- `[device-id.ts:getDeviceId]`
- `[device-id.ts:resetDeviceIdCacheForTests]`
- `[errors.ts:ApiError]`
- `[errors.ts:ConflictRetryError]`
- `[storage.ts:StorageService]`
- `[sync.ts:SyncOperationType]`
- `[sync.ts:SyncOperationAction]`
- `[sync.ts:SyncOperationMeta]`
- `[sync.ts:SyncOperation]`
- `[sync.ts:SyncStatus]`
- `[sync.ts:SyncState]`
- `[sync.ts:SyncService]`

## Invariants
- [auth.test.ts:212]: `// Assert rejection before advancing timers (avoids unhandled rejection)`
- [cross-window-sync.test.ts:23]: `/* eslint-disable @typescript-eslint/no-explicit-any, global-require, @typesc...`
- [cross-window-sync.test.ts:27]: `export {}; // make this a module so the `require` declaration is module-scoped`
- [cross-window-sync.test.ts:29]: `declare let require: any;`
- [sync.test.ts:37]: `declare let require: any;`
- [sync.test.ts:105]: `// run processQueue explicitly and assert deterministic post-conditions)`

## Side Effects
- [WorkspaceSync.test.ts:39]: `query: jest.fn().mockResolvedValue([]),`
- [api.test.ts:42]: `// Mock global fetch`
- [api.test.ts:43]: `globalThis.fetch = jest.fn();`
- [api.test.ts:54]: `(globalThis.fetch as jest.Mock).mockResolvedValue({`
- [api.ts:89]: `const response = await fetch(`${API_URL}${endpoint}`, {`
- [api.ts:223]: `// No session at all -> nothing authoritative to fetch; keep the cache.`
- [api.ts:289]: `query: {`
- [auth.test.ts:383]: `(globalThis as unknown as { fetch: jest.Mock }).fetch = jest.fn();`
- [auth.test.ts:391]: `(globalThis as unknown as { fetch: jest.Mock }).fetch,`
- [auth.test.ts:399]: `(globalThis as unknown as { fetch: jest.Mock }).fetch.mockResolvedValue({`

## Verification
- Run: `bazel test //apps/suites/tabula/extension/src/services/...`
