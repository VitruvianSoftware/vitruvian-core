# Vessels

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/vessels`.

## Interface
- `[ais-live.js:aisLiveProxy]`
- `[ais-store.js:AISSTREAM_CACHE_MAX]`
- `[ais-store.js:AISSTREAM_STALE_MS]`
- `[ais-store.js:ingestAisStreamEnvelope]`
- `[ais-store.js:readAisTrack]`
- `[ais-store.js:aisStreamRows]`
- `[ais-store.js:newestAisPositionAt]`

## Invariants
- None

## Side Effects
- [ais-live.js:27]: `import { clampInt } from '../common/query.js';`
- [ais-live.js:100]: `const incoming = new URL(req.url || '', 'http://localhost');`
- [ais-live.js:116]: `error: 'mmsi query param required',`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/vessels/...`
