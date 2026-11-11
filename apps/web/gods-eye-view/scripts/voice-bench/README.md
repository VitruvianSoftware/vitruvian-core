# Voice Bench

## Overview
Component package providing implementation for `apps/web/gods-eye-view/scripts/voice-bench`.

## Interface
- `[grade.mjs:matchArgs]`
- `[grade.mjs:call]`
- `[grade.mjs:where]`
- `[grade.mjs:expectLabel]`
- `[grade.mjs:expectedToolNames]`
- `[grade.mjs:gradeCore]`
- `[grade.mjs:gradeDialogue]`
- `[grade.mjs:validateArgs]`
- `[grade.mjs:validateCall]`
- `[grade.mjs:LOOKUP_TOOLS]`
- `[grade.mjs:REFUSAL_RE]`
- `[grade.mjs:gradeCoverage]`
- `[keys.mjs:providerKey]`
- `[phrases.mjs:CORE_PHRASES]`
- `[phrases.mjs:coverageRubric]`
- `[phrases.mjs:COVERAGE_PROBE]`
- `[phrases.mjs:DIALOGUES]`
- `[phrases.mjs:dialogueResult]`
- `[phrases.mjs:GEOMETRY_PHRASES]`
- `[phrases.mjs:OVERPASS_PHRASES]`
- Subdirectory: [adapters](./adapters/README.md)

## Invariants
- [phrases.mjs:124]: `// — multi-intent (assert ALL tools fire before speech) —`

## Side Effects
- [phrases.mjs:50]: `{ phrase: 'Take me to Tokyo', expect: 'fly_to_location', typedArgs: [where('f...`
- [phrases.mjs:133]: `typedArgs: [where('set_hud', (a) => a.visible === 'off'), where('fly_to_locat...`
- [phrases.mjs:403]: `expect: 'nearest transit vehicle (no transit query/context today) — honest ot...`
- [productionConfig.mjs:27]: `* handler (`server/providers/openai/realtime.js`) with a fake upstream fetch`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/scripts/voice-bench/...`
