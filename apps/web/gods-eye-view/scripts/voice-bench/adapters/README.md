# Adapters

## Overview
Component package providing implementation for `apps/web/gods-eye-view/scripts/voice-bench/adapters`.

## Interface
- `[geminiLive.mjs:createGeminiLiveAdapter]`
- `[localChat.mjs:createOpenAiChatAdapter]`
- `[localChat.mjs:createOllamaAdapter]`
- `[openaiRealtime.mjs:newTurnResult]`
- `[openaiRealtime.mjs:createOpenAiRealtimeAdapter]`

## Invariants
- None

## Side Effects
- [geminiLive.mjs:133]: `ws.on('unexpected-response', (_req, res) => shutdown(`HTTP ${res.statusCode}`));`
- [localChat.mjs:126]: `const res = await fetch(`${baseUrl.replace(/\/$/, '')}/chat/completions`, {`
- [localChat.mjs:135]: `if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(...`
- [localChat.mjs:208]: `export function createOllamaAdapter({ model, baseUrl = 'http://localhost:1143...`
- [openaiRealtime.mjs:121]: `ws.on('unexpected-response', (_req, res) => shutdown(`HTTP ${res.statusCode}`));`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/scripts/voice-bench/adapters/...`
