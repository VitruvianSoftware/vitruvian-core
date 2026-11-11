# Maps

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/maps`.

## Interface
- `[availability.js:photorealUnavailableReason]`
- `[catalog.js:MAP_STACKS]`
- `[controller.js:MapSourceController]`
- `[credits.js:createMapCredits]`
- `[defaultSources.js:createDefaultMapSources]`
- `[google3d.js:selectMapStartupRoute]`
- `[google3d.js:loadPhotorealisticTileset]`
- `[google3d.js:createGoogleDirectTileset]`
- `[google3d.js:createGoogleTokenTileset]`
- `[google3d.js:createGoogleIonTileset]`
- `[googleTokens.js:GOOGLE_TOKEN_PATH]`
- `[googleTokens.js:createGoogleTokenSource]`
- `[imagery.js:ESRI_ATTRIBUTION_HTML]`
- `[imagery.js:createOsmImagery]`
- `[imagery.js:createEsriImagery]`
- `[imagery.js:createIonImagery]`
- `[imageryComparison.js:acquireImageryComparison]`
- `[imageryHost.js:NO_IMAGERY_HOST]`
- `[imageryHost.js:resolveImageryHost]`
- `[registry.js:indexMapSources]`

## Invariants
- [controller.test.mjs:24]: `import assert from 'node:assert/strict';`
- [controller.test.mjs:144]: `assert.equal(env.controller.getActiveId(), 'custom');`
- [controller.test.mjs:145]: `assert.equal(env.viewer.terrainProvider.id, 'terrain');`
- [googleTokens.test.mjs:24]: `import assert from 'node:assert/strict';`
- [googleTokens.test.mjs:50]: `assert.equal(await tokens.token(), 'first');`
- [googleTokens.test.mjs:51]: `assert.equal(await tokens.token(), 'first');`
- [imageryHost.test.mjs:24]: `import assert from 'node:assert/strict';`
- [imageryHost.test.mjs:33]: `assert.deepEqual(host, { collection: imageryLayers, kind: 'globe' });`
- [imageryHost.test.mjs:42]: `assert.deepEqual(host, { collection: imageryLayers, kind: 'tileset' });`
- [map-subscription-ownership.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [googleTokens.js:50]: `fetchImpl = (...args) => fetch(...args),`
- [googleTokens.test.mjs:88]: `assert.equal(cancelled, true, `HTTP ${status} body released`);`
- [imagery.js:71]: `// Bing otherwise follows the page's HTTP scheme on localhost. Resolve its`
- [sourceFactories.test.mjs:142]: `tileProtocol: 'http',`
- [sourceFactories.test.mjs:165]: `assert.fail('Bing must not inherit the local HTTP page protocol'),`
- [sourceFactories.test.mjs:220]: `assert.equal(endpoint.options.tileProtocol, 'http');`
- [terrain.js:58]: `* and each `{z}/{x}/{y}.terrain` fetch inherit it (see `terrainRetry.js`).`
- [terrainRetry.js:28]: `* with HTTP 429 for a few dozen tiles at once. Cesium marks each throttled`
- [terrainRetry.js:33]: `* `retryAttempts`) that `getDerivedResource` copies onto every tile fetch, and`
- [terrainRetry.js:65]: `* Parses a `Retry-After` header (delay-seconds or HTTP-date) into a wait in`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/maps/...`
