# Agent

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/agent`.

## Interface
- `[worldPacket.js:TRACKABLE_FAMILIES]`
- `[worldPacket.js:withContextModeVocabulary]`
- `[worldPacket.js:collectTrackedEntities]`
- `[worldPacket.js:activeContactsWindow]`
- `[worldPacket.js:getWorldPacket]`

## Invariants
- [worldPacket.test.mjs:24]: `import assert from 'node:assert/strict';`
- [worldPacket.test.mjs:94]: `assert.deepEqual(withoutVoicePresentation(voice), packet);`
- [worldPacket.test.mjs:95]: `assert.equal(packet.context.mode, 'contacts');`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/agent/...`
