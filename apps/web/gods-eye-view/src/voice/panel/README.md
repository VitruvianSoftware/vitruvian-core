# Panel

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/voice/panel`.

## Interface
- `[actionObserver.js:createPanelActionObserver]`
- `[host.js:createVoicePanelHost]`
- `[inactivity.js:createVoiceInactivity]`
- `[manualPanel.js:createManualVoicePanel]`
- `[nativeActivity.js:observeNativeActivity]`
- `[preferences.js:VOICE_PREVIEW_STORAGE_KEY]`
- `[preferences.js:VOICE_TIMEOUT_STORAGE_KEY]`
- `[preferences.js:createVoicePreferences]`
- `[preferences.js:bindPreferenceControls]`

## Invariants
- [actionObserver.test.mjs:24]: `import assert from 'node:assert/strict';`
- [actionObserver.test.mjs:48]: `assert.equal(this, receiver);`
- [actionObserver.test.mjs:49]: `assert.equal(received, args);`
- [host.test.mjs:25]: `import assert from 'node:assert/strict';`
- [host.test.mjs:188]: `assert.equal(baseline.panel, false);`
- [host.test.mjs:190]: `assert.equal(exists('#gev-voice-control'), true);`
- [inactivity.test.mjs:24]: `import assert from 'node:assert/strict';`
- [inactivity.test.mjs:67]: `assert.equal([...f.timers.values()][0].delay, 300000);`
- [inactivity.test.mjs:68]: `assert.equal(f.idle.snapshot().deadline, 300100);`
- [manualPanel.test.mjs:25]: `import assert from 'node:assert/strict';`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/voice/panel/...`
