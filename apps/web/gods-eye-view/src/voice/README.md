# Voice

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/voice`.

## Interface
- `[actionSchemas.js:GEV_ACTION_SCHEMAS]`
- `[actionSchemas.js:createActionTools]`
- `[areaActions.js:spokenArea]`
- `[areaActions.js:createVoiceAreas]`
- `[areaCandidateContract.js:MAX_AREA_CANDIDATE_ID_LENGTH]`
- `[areaCandidateContract.js:AREA_CANDIDATE_ID_PATTERN]`
- `[areaCandidateContract.js:isAreaCandidateId]`
- `[chatAttachments.js:bindChatAttachments]`
- `[chatControl.js:bindChatControl]`
- `[chatPreferences.js:bindChatPreferences]`
- `[cloudVoiceAuth.js:CLOUD_VOICE_AUTH_STORAGE_KEY]`
- `[cloudVoiceAuth.js:readStoredCloudVoiceAuthMode]`
- `[cloudVoiceAuth.js:writeStoredCloudVoiceAuthMode]`
- `[commands.js:createVoiceCommands]`
- `[control.js:ASSISTANT_NAME]`
- `[control.js:VOICE_VISUALIZER_BARS]`
- `[control.js:voiceStatusLabel]`
- `[control.js:createVoiceControl]`
- `[deixis.js:resolveDeicticArgs]`
- `[earcon.js:createEarcon]`
- Subdirectory: [panel](./panel/README.md)

## Invariants
- [actionSchemas.test.mjs:25]: `import assert from 'node:assert/strict';`
- [actionSchemas.test.mjs:58]: `assert.equal(`
- [actionSchemas.test.mjs:96]: `assert.equal(tool.description, 'Navigate');`
- [aircraftIdentityNarration.test.mjs:24]: `import assert from 'node:assert/strict';`
- [aircraftIdentityNarration.test.mjs:38]: `assert.ok(start >= 0, 'aircraft identity honesty instruction is missing');`
- [aircraftIdentityNarration.test.mjs:40]: `assert.match(text, /get_entity_context/);`
- [analystAccessors.test.mjs:24]: `import assert from 'node:assert/strict';`
- [analystAccessors.test.mjs:41]: `assert.ok(Object.hasOwn(record, field), `${layerId} record lacks ${field}`);`
- [analystAccessors.test.mjs:42]: `assert.equal(typeof record.lat, 'number');`
- [analystCardLocale.test.mjs:25]: `import assert from 'node:assert/strict';`

## Side Effects
- [actionSchemas.js:60]: `query: {`
- [actionSchemas.test.mjs:91]: `parameters: { properties: { query: { description: 'A place' } } },`
- [actionSchemas.test.mjs:97]: `assert.equal(tool.parameters.properties.query.description, 'A place');`
- [actionSchemas.test.mjs:98]: `assert.equal(tool.parameters.properties.query.type, 'string');`
- [areaActions.js:237]: `async function resolveNamedOutline(query, { level, levelHint, signal }) {`
- [areaActions.js:249]: `target: query,`
- [areaActions.js:264]: `error: `Could not find "${query}".`,`
- [areaActions.test.mjs:151]: `query: 'Bagmati province',`
- [areaActions.test.mjs:213]: `query: 'Bagmati province',`
- [areaActions.test.mjs:223]: `query: 'Bagmati province',`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/voice/...`
