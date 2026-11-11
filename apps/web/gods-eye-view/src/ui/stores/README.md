# Stores

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui/stores`.

## Interface
- `[awarenessDirection.js:useAwarenessDirectionStore]`
- `[bhoteKoshiPanel.js:useBhoteKoshiPanelStore]`
- `[cctv.js:useCctvStore]`
- `[celestialRing.js:useCelestialRingStore]`
- `[cockpit.js:useCockpitStore]`
- `[context.js:useContextStore]`
- `[dataPacks.js:useDataPacksStore]`
- `[display.js:useDisplayStore]`
- `[firstRun.js:useFirstRunStore]`
- `[globeActions.js:useGlobeActionsStore]`
- `[hud.js:useHudStore]`
- `[imagerySplit.js:useImagerySplitStore]`
- `[locale.js:useLocaleStore]`
- `[location.js:useLocationStore]`
- `[missionReplay.js:useMissionReplayStore]`
- `[owners.js:createOwners]`
- `[panelChrome.js:usePanelChromeStore]`
- `[panels.js:usePanelStore]`
- `[pointerReticle.js:usePointerReticleStore]`
- `[providerSettings.js:useProviderSettingsStore]`

## Invariants
- [owners.test.mjs:26]: `import assert from 'node:assert/strict';`
- [owners.test.mjs:45]: `assert.deepEqual(calls, [`
- [owners.test.mjs:55]: `assert.equal(act('pick', 'jazz'), 'kept jazz');`
- [panels.test.mjs:24]: `import assert from 'node:assert/strict';`
- [panels.test.mjs:38]: `assert.equal(store.openPanelId('left'), 'scene-panel');`
- [panels.test.mjs:40]: `assert.equal(store.openPanelId('right'), null);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/stores/...`
