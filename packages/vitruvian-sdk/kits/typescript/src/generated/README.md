# Generated

## Overview
Component package providing implementation for `packages/vitruvian-sdk/kits/typescript/src/generated`.

## Interface
- `[manifest.ts:ToolManifest]`
- `[manifest.ts:readToolManifest]`
- `[manifest.ts:Contributes]`
- `[manifest.ts:readContributes]`
- `[manifest.ts:StatusContribution]`
- `[manifest.ts:readStatusContribution]`
- `[manifest.ts:SlotContribution]`
- `[manifest.ts:readSlotContribution]`
- `[manifest.ts:Command]`
- `[manifest.ts:readCommand]`
- `[manifest.ts:Panel]`
- `[manifest.ts:readPanel]`
- `[manifest.ts:Preference]`
- `[manifest.ts:readPreference]`
- `[manifest.ts:PreferenceOption]`
- `[manifest.ts:readPreferenceOption]`
- `[manifest.ts:Runtime]`
- `[manifest.ts:readRuntime]`
- `[messages.ts:JSONValue]`
- `[messages.ts:ShapeError]`

## Invariants
- None

## Side Effects
- [manifest.ts:303]: `exec: string;`
- [manifest.ts:310]: `exec: expectString(object["exec"], `${where}.exec`),`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/kits/typescript/src/generated/...`
