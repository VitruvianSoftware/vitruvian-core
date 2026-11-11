# Utils

## Overview
Component package providing implementation for `apps/suites/tabula/extension/src/utils`.

## Interface
- `[emoji.ts:extractLeadingEmoji]`
- `[favicon.ts:getFaviconSrc]`
- `[markdown.ts:MarkdownValidationResult]`
- `[markdown.ts:parseMarkdown]`
- `[router.ts:getSpaceIdFromUrl]`
- `[router.ts:getRelayIdFromUrl]`
- `[router.ts:clearRelayIdFromUrl]`
- `[router.ts:setSpaceIdInUrl]`
- `[router.ts:clearSpaceIdFromUrl]`
- `[router.ts:getDashboardUrlWithSpace]`

## Invariants
- None

## Side Effects
- [router.test.ts:45]: `// lets http(s) documents rewrite their query string (a chrome-extension://`
- [router.test.ts:46]: `// document URL would throw SecurityError even for query changes), so the`
- [router.test.ts:47]: `// tests run on jest's default http://localhost origin — the router helpers`
- [router.ts:29]: `* Gets the spaceId from the current URL query parameters.`
- [router.ts:38]: `* Gets the relayId from the current URL query parameters. The dashboard is`

## Verification
- Run: `bazel test //apps/suites/tabula/extension/src/utils/...`
