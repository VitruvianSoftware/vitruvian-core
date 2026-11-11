# Mapillary

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/mapillary`.

## Interface
- `[tiles.js:TILE_MAX_BYTES]`
- `[tiles.js:TILE_UPSTREAM_CONCURRENCY]`
- `[tiles.js:TILE_TTL_MS]`
- `[tiles.js:TILE_MEMORY_MAX_TILES]`
- `[tiles.js:TILE_MEMORY_MAX_TILE_BYTES]`
- `[tiles.js:MAX_RETRY_AFTER_SEC]`
- `[tiles.js:mapillaryToken]`
- `[tiles.js:TileUpstreamError]`
- `[tiles.js:retryAfterWait]`
- `[tiles.js:parseTilePath]`
- `[tiles.js:fetchTile]`
- `[tiles.js:_resetTileCacheForTest]`
- `[trim.js:stripTileLayers]`

## Invariants
- None

## Side Effects
- [tiles.js:23]: `import { readResponseBytesCapped } from '../common/http.js';`
- [tiles.js:58]: `super(message || `Mapillary tiles HTTP ${status}`);`
- [tiles.js:66]: `/** Seconds a Retry-After header asks for (an integer or an HTTP date), else ...`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/mapillary/...`
