# Gemini

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/gemini`.

## Interface
- `[chat.js:GEMINI_DEFAULT_PER_MIN]`
- `[chat.js:validChatContents]`
- `[chat.js:createGeminiChatHandler]`
- `[config.js:GEMINI_LIVE_MODEL_DEFAULT]`
- `[config.js:GEMINI_TOKEN_ENDPOINT]`
- `[config.js:GEMINI_LIVE_WEBSOCKET_URL]`
- `[config.js:normalizeGeminiModel]`
- `[config.js:createGeminiLiveConfig]`
- `[realtime.js:createGeminiTokenHandler]`
- `[request.js:isGeminiRequestOriginAllowed]`
- `[request.js:readGeminiTokenRequest]`

## Invariants
- None

## Side Effects
- [realtime.js:47]: `fetchImpl = (...args) => fetch(...args),`
- [realtime.js:156]: `// A fetch implementation can ignore abort. Bound this caller's wait and`
- [request.js:46]: `const protocol = req.socket?.encrypted ? 'https:' : 'http:';`
- [request.js:52]: `secFetchSite: req.headers?.['sec-fetch-site'],`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/gemini/...`
