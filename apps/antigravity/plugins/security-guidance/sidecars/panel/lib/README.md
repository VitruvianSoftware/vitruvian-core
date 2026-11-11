# Lib

## Overview
Component package providing implementation for `apps/antigravity/plugins/security-guidance/sidecars/panel/lib`.

## Interface
- `[core.mjs:BUILTIN_PATTERNS]`
- `[core.mjs:hasInlineSuppression]`
- `[core.mjs:scanContentForPatterns]`
- `[core.mjs:scanDiffForVulnerabilities]`
- `[core.mjs:filterSuppressedFindings]`
- `[core.mjs:summariseSecurityState]`
- `[openui.mjs:escapeHtml]`
- `[openui.mjs:resolveDataPath]`
- `[openui.mjs:parseOpenUILang]`
- `[openui.mjs:renderNodeToHtml]`
- `[openui.mjs:renderOpenUIFragment]`
- `[openui.mjs:compileToHtml]`
- `[openui.mjs:openuiLiteral]`
- `[openui.mjs:toOpenUILang]`

## Invariants
- [core.test.mjs:23]: `import assert from "node:assert/strict";`
- [core.test.mjs:36]: `assert.ok(BUILTIN_PATTERNS.length >= 15);`
- [core.test.mjs:56]: `assert.ok(ids.has(expected), `missing pattern ${expected}`);`
- [openui.test.mjs:23]: `import assert from "node:assert/strict";`
- [openui.test.mjs:37]: `assert.equal(root.$component, "Card");`
- [openui.test.mjs:50]: `assert.deepEqual(parsed.order, ["root", "hdr"]);`

## Side Effects
- [core.mjs:69]: `id: "command-injection-curl-sh",`
- [core.mjs:73]: `regex: /\b(?:curl|wget)\b[^\n|]*\|\s*(?:sudo\s+)?(?:ba)?sh\b/,`
- [core.mjs:131]: `id: "python-subprocess-shell",`
- [core.test.mjs:43]: `"command-injection-curl-sh",`
- [core.test.mjs:49]: `"python-subprocess-shell",`
- [core.test.mjs:50]: `"node-child-process-exec",`
- [openui.mjs:274]: `if (node.name === "Query") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/security-guidance/sidecars/panel/lib/...`
