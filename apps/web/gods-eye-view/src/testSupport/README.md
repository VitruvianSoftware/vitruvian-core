# Testsupport

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/testSupport`.

## Interface
- `[applicationHtml.mjs:renderApplicationHtml]`
- `[applicationHtml.mjs:readApplicationHtml]`
- `[domAssert.mjs:assertSameNode]`
- `[geminiIntegrationFixture.mjs:turnOfEventLoop]`
- `[geminiIntegrationFixture.mjs:nativeIntegrationFixture]`
- `[geminiIntegrationFixture.mjs:assertSuccessfulZoom]`
- `[googleStreetViewFakes.mjs:fakeStreetViewLibrary]`
- `[googleStreetViewFakes.mjs:fakeMapsLoader]`
- `[googleStreetViewFakes.mjs:fakeHost]`
- `[hudReadouts.mjs:hudReadouts]`
- `[kartaViewFakes.mjs:fakeHost]`
- `[kartaViewFakes.mjs:until]`
- `[panelState.mjs:presentPanelLocally]`
- `[panoramaxFixtures.mjs:encodePanoramaxTile]`
- `[panoramaxFixtures.mjs:stacItem]`
- `[radioLayerHarness.mjs:radioStationRow]`
- `[radioLayerHarness.mjs:withRadioLayer]`
- `[readLayerSource.mjs:readLayerSource]`
- `[readRealtimeSource.mjs:readRealtimeSource]`
- `[readShellSource.mjs:readShellSource]`

## Invariants
- [domAssert.mjs:23]: `import assert from 'node:assert/strict';`
- [domAssert.mjs:31]: `* Assert that two DOM nodes (or a node and null) are the same. Never hand`
- [domAssert.mjs:32]: `* happy-dom nodes to assert.equal or deepEqual: a failure prints both, and a`
- [geminiIntegrationFixture.mjs:23]: `import assert from 'node:assert/strict';`
- [geminiIntegrationFixture.mjs:62]: `assert.ok(`
- [geminiIntegrationFixture.mjs:161]: `assert.equal(`
- [vueDom.mjs:27]: `* Call it from `before`/`after`, since other suites assert there is no DOM.`
- [wildlifeBillboardModel.mjs:23]: `import assert from 'node:assert/strict';`
- [wildlifeBillboardModel.mjs:63]: `assert.equal(points.delete(point), true);`

## Side Effects
- [radioLayerHarness.mjs:51]: `const originalFetch = globalThis.fetch;`
- [radioLayerHarness.mjs:77]: `globalThis.fetch = async (url) =>`
- [radioLayerHarness.mjs:116]: `globalThis.fetch = originalFetch;`
- [registerDom.mjs:27]: `GlobalRegistrator.register({ url: 'http://localhost/' });`
- [vueDom.mjs:30]: `GlobalRegistrator.register({ url: 'http://localhost/' });`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/testSupport/...`
