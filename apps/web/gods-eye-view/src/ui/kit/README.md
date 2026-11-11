# Kit

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui/kit`.

## Interface
- `[UiSelect.js:UiSelect]`
- `[UiSlider.js:UiSlider]`
- `[rail.js:RAIL_PANEL_OPEN_TOOLTIP_DELAY_MS]`

## Invariants
- [UiBadge.test.mjs:24]: `import assert from 'node:assert/strict';`
- [UiBadge.test.mjs:45]: `assert.deepEqual(badge.classes(), [`
- [UiBadge.test.mjs:51]: `assert.equal(badge.attributes('role'), 'status');`
- [UiButton.test.mjs:24]: `import assert from 'node:assert/strict';`
- [UiButton.test.mjs:56]: `assert.equal(button.attributes('aria-pressed'), 'false');`
- [UiButton.test.mjs:57]: `assert.equal(button.classes().includes('active'), false);`
- [UiChip.test.mjs:24]: `import assert from 'node:assert/strict';`
- [UiChip.test.mjs:43]: `assert.deepEqual(chip.classes(), ['ui-chip', 'gev-voice-card-chip']);`
- [UiChip.test.mjs:44]: `assert.equal(chip.attributes('data-tone'), 'ok');`
- [UiRail.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/kit/...`
