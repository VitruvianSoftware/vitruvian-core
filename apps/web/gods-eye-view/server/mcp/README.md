# Mcp

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/mcp`.

## Interface
- `[panelKey.js:DEFAULT_PANEL_KEY_FILE]`
- `[panelKey.js:sharedPanelKey]`
- `[plugin.js:isLocalMcpRequest]`
- `[plugin.js:localMcpPlugin]`
- `[server.js:createLocalMcpServer]`
- `[services.js:DEFAULT_API_BASE]`
- `[services.js:createApiFetch]`
- `[services.js:createLocalToolServices]`
- `[stdio.js:describeRequest]`
- `[stdio.js:serveStdio]`
- `[stdio.js:parseArgs]`

## Invariants
- None

## Side Effects
- [panelKey.js:41]: `const text = fs.readFileSync(file, 'utf8').trim();`
- [panelKey.js:53]: `fd = fs.openSync(lock, 'wx', 0o600);`
- [panelKey.js:72]: `fs.renameSync(tmp, file);`
- [plugin.js:62]: `hostUrl = new URL(`http://${host}`);`
- [plugin.js:75]: `['http:', 'https:'].includes(originUrl.protocol) &&`
- [plugin.js:129]: `const request = new Request(`http://${host}/mcp`, {`
- [services.js:35]: `export const DEFAULT_API_BASE = 'http://localhost:4173';`
- [services.js:44]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [services.js:47]: `if (!['http:', 'https:'].includes(base.protocol))`
- [stdio.js:26]: `*   npm run mcp -- [--api-base http://localhost:4173]`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/mcp/...`
