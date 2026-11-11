# Openai

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/openai`.

## Interface
- `[chat.js:chatSchema]`
- `[chat.js:createOpenAiChatHandler]`
- `[codex-auth.js:codexAuthPath]`
- `[codex-auth.js:preferCodexOAuth]`
- `[codex-auth.js:readCodexOAuthAccessToken]`
- `[codex-auth.js:resolveCodexExecutable]`
- `[codex-auth.js:startCodexChatGptLogin]`
- `[codex-auth.js:createCodexOAuthLogin]`
- `[toolDescriptions.js:ACTION_DESCRIPTIONS]`
- `[tools.js:GEV_REALTIME_TOOLS]`
- `[tools.js:realtimeSessionTools]`
- `[tools.js:OVERPASS_ONLY_TOOLS]`
- `[tools.js:offeredTools]`
- `[tools.js:realtimeTools]`

## Invariants
- [instructions.js:38]: `'Do not require a wake phrase. Treat direct commands like "zoom into London" ...`

## Side Effects
- [codex-auth.js:23]: `import { spawn } from 'node:child_process';`
- [codex-auth.js:179]: `spawnImpl = spawn,`
- [codex-auth.js:234]: `child.once('spawn', () => {`
- [debug-log.js:74]: `// chasing query, label, say, display, or future tool-specific fields.`
- [hud-summary.js:143]: `const response = await fetch('https://api.openai.com/v1/responses', {`
- [hud-summary.js:169]: `console.warn(`[hud-summary] upstream HTTP ${response.status}`);`
- [instructions.js:51]: `'WORLD QUERIES — the query tools (get_weather, get_wind, search_places, place...`
- [instructions.js:62]: `'POINTING: pointer_context says what the cursor is on (pointing:<kind>: resol...`
- [instructions.js:87]: `'"Track/follow <something specific>" (a callsign, ship name, satellite name) ...`
- [rate-limit.js:60]: `* @param {import('http').IncomingMessage} req`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/openai/...`
