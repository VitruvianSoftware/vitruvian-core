# Lib

## Overview
Component package providing implementation for `apps/suites/tabula/web/lib`.

## Interface
- `[auth.ts:User]`
- `[auth.ts:AuthResponse]`
- `[auth.ts:AuthService]`
- `[data.ts:getDataSourceInfo]`
- `[data.ts:getWorkspaces]`
- `[data.ts:getWorkspace]`
- `[data.ts:getStats]`
- `[data.ts:exportWorkspaces]`
- `[data.ts:downloadFile]`
- `[data.ts:seedDemoData]`
- `[data.ts:DataService]`
- `[json-script.ts:escapeJsonForScript]`
- `[runtime-config.ts:RUNTIME_CONFIG_ELEMENT_ID]`
- `[runtime-config.ts:getApiUrl]`
- `[runtime-config.ts:__resetRuntimeConfigCacheForTests]`
- `[safe-href.ts:safeHref]`
- `[security-headers.ts:apiOriginFor]`
- `[security-headers.ts:buildContentSecurityPolicy]`
- `[security-headers.ts:securityHeaders]`
- `[sharing.ts:SpaceRole]`

## Invariants
- None

## Side Effects
- [auth.test.ts:131]: `origin: "http://localhost:8080",`
- [data.test.ts:48]: `// Mock fetch`
- [data.test.ts:49]: `global.fetch = jest.fn();`
- [data.test.ts:103]: `it("should fetch from chrome storage", async () => {`
- [data.ts:84]: `* Fetch all workspaces from available storage`
- [data.ts:102]: `const res = await fetch(`${getApiUrl()}/workspaces`, {`
- [runtime-config.server.test.ts:51]: `expect(getApiUrl()).toBe("http://localhost:8080/api/v1");`
- [runtime-config.test.ts:61]: `expect(getApiUrl()).toBe("http://localhost:8080/api/v1");`
- [runtime-config.test.ts:66]: `expect(getApiUrl()).toBe("http://localhost:8080/api/v1");`
- [runtime-config.test.ts:72]: `expect(getApiUrl()).toBe("http://localhost:8080/api/v1");`

## Verification
- Run: `bazel test //apps/suites/tabula/web/lib/...`
