# Server

## Overview
Component package providing implementation for `apps/web/gods-eye-view/tests/server`.

## Interface
- Internal implementation components

## Invariants
- [image.test.mjs:35]: `import assert from 'node:assert/strict';`
- [image.test.mjs:53]: `assert.ok(start >= 0, 'the Dockerfile has a runtime stage');`
- [image.test.mjs:145]: `assert.fail(`server.mjs did not start from the image layout:\n${output}`);`

## Side Effects
- [image.test.mjs:36]: `import { execFileSync, spawn } from 'node:child_process';`
- [image.test.mjs:38]: `import http from 'node:http';`
- [image.test.mjs:57]: `const match = /^COPY\s+(.+)$/i.exec(line);`
- [no-network.mjs:30]: `import http from 'node:http';`
- [no-network.mjs:37]: `// A loopback fetch reaches a server the test itself runs.`
- [no-network.mjs:38]: `const realFetch = globalThis.fetch;`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/tests/server/...`
