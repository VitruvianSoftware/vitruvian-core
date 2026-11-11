# Mcp

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/tools/mcp`.

## Interface
- `[http.js:createMcpHttpHandler]`
- `[protocol.js:MCP_PROTOCOL_VERSIONS]`
- `[protocol.js:toMcpTools]`
- `[protocol.js:createMcpServer]`
- `[protocol.js:parseErrorResponse]`

## Invariants
- [mcp.test.mjs:23]: `import assert from 'node:assert/strict';`
- [mcp.test.mjs:72]: `assert.deepEqual(known.result, {`
- [mcp.test.mjs:81]: `assert.equal(unknown.result.protocolVersion, MCP_PROTOCOL_VERSIONS[0]);`

## Side Effects
- [http.js:24]: `* Stateless Streamable HTTP transport for an MCP server: one JSON-RPC message`
- [index.js:31]: `export { createMcpHttpHandler } from './http.js';`
- [mcp.test.mjs:142]: `assert.deepEqual(custom._meta, { kind: 'query', seen: 'count' });`
- [mcp.test.mjs:173]: `test('the HTTP transport accepts one JSON message per POST', async () => {`
- [mcp.test.mjs:177]: `new Request('http://localhost/mcp', {`
- [protocol.js:27]: `* views (`ui://` resources) that tools name in `_meta.ui.resourceUri`. Transp...`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/tools/mcp/...`
