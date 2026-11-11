# App

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/app`.

## Interface
- `[application.js:createApplication]`
- `[atmosphereCompat.js:isAppleMobilePlatform]`
- `[atmosphereCompat.js:probeOutParamVaryingLinkFailure]`
- `[atmosphereCompat.js:shouldDisableModelAtmosphere]`
- `[atmosphereCompat.js:applyModelAtmosphereWorkaround]`
- `[catalog.js:createLayerCatalog]`
- `[catalog.js:catalogControlServices]`
- `[constructCatalog.js:LOCAL_ONLY_LAYER_METADATA]`
- `[constructCatalog.js:APPLICATION_LAYER_METADATA]`
- `[constructCatalog.js:createApplicationCatalog]`
- `[controls.js:createApplicationControls]`
- `[data.js:createApplicationData]`
- `[embed.js:isEmbedded]`
- `[embed.js:isEmbeddedInline]`
- `[embed.js:panelAwareVisibility]`
- `[embed.js:keepPanelRendering]`
- `[embed.js:applyView]`
- `[embed.js:installViews]`
- `[errors.js:describeError]`
- `[globePanelRuntime.js:panelRuntime]`
- Subdirectory: [layers](./layers/README.md)

## Invariants
- [application.test.mjs:24]: `import assert from 'node:assert/strict';`
- [application.test.mjs:84]: `assert.equal(result.status, 0, result.stderr);`
- [application.test.mjs:88]: `assert.throws(() => createApplication({}), /Missing scene constructor/);`
- [atmosphereCompat.test.mjs:24]: `import assert from 'node:assert/strict';`
- [atmosphereCompat.test.mjs:82]: `assert.equal(isAppleMobilePlatform(IPAD_OS12), true);`
- [atmosphereCompat.test.mjs:83]: `assert.equal(isAppleMobilePlatform(IPAD_DESKTOP_MODE), true);`
- [catalog.test.mjs:24]: `import assert from 'node:assert/strict';`
- [catalog.test.mjs:38]: `assert.deepEqual(catalog.layers, [first]);`
- [catalog.test.mjs:39]: `assert.equal(catalog.get('first'), first);`
- [constructCatalog.test.mjs:25]: `import assert from 'node:assert/strict';`

## Side Effects
- [application.test.mjs:74]: `globalThis.fetch = () => { throw new Error('unexpected request'); };`
- [embed.js:243]: `(await run('track_entity', { query: view.follow.id, layerId }))?.ok ===`
- [embed.test.mjs:67]: `test('embed mode is opt-in by query parameter', () => {`
- [embed.test.mjs:405]: `['track_entity', { query: 'ae1234', layerId: 'military' }],`
- [globePanelRuntime.js:206]: `const nativeFetch = window.fetch.bind(window);`
- [globePanelRuntime.js:207]: `window.fetch = async (input, init = {}) => {`
- [operations.js:60]: `searchAndFlyTo: (viewer, query, options = {}) =>`
- [operations.js:61]: `searchAndFlyTo(viewer, query, {`
- [operations.test.mjs:27]: `function requests(terrain, boundaries = { query: async () => [] }) {`
- [operations.test.mjs:141]: `query: async () => {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/app/...`
