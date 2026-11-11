# Rail

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui/rail`.

## Interface
- `[classToggle.js:vClassToggle]`
- `[fieldValue.js:vFieldValue]`
- `[focusSafeChildren.js:vFocusSafeChildren]`
- `[panelState.js:applyPanelState]`
- `[panelState.js:followPanelState]`
- `[panelState.js:vPanelState]`
- `[panelState.js:prefersCollapsed]`
- `[panelState.js:readPanelState]`
- `[rangeValue.js:vRangeValue]`
- `[statusText.js:vStatusText]`
- `[utcClock.js:utcClock]`

## Invariants
- [fieldValue.test.mjs:27]: `import assert from 'node:assert/strict';`
- [fieldValue.test.mjs:44]: `assert.equal(field.value, '98.5');`
- [fieldValue.test.mjs:49]: `assert.equal(field.value, '101.1', 'typing stands');`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/rail/...`
