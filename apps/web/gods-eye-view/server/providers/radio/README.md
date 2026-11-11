# Radio

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/radio`.

## Interface
- `[catalog.js:parseRadioPriorityCountries]`
- `[catalog.js:createRadioProxyMiddleware]`
- `[constants.js:RADIO_DIRECTORY_CACHE_MS]`
- `[constants.js:RADIO_DIRECTORY_STALE_MS]`
- `[constants.js:RADIO_MIRROR_CACHE_MS]`
- `[constants.js:RADIO_FETCH_TIMEOUT_MS]`
- `[constants.js:RADIO_RESPONSE_MAX_BYTES]`
- `[constants.js:RADIO_DIRECTORY_LIMIT]`
- `[constants.js:RADIO_CATALOG_MIN_SUCCESSFUL_QUERIES]`
- `[constants.js:RADIO_CATALOG_HEALTHY_MIN_STATIONS]`
- `[constants.js:RADIO_USER_AGENT]`
- `[constants.js:RADIO_REJECTED_STATION_COUNT_MAX]`
- `[constants.js:RADIO_FALLBACK_MIRRORS]`
- `[transport.js:radioMirrorOrigin]`
- `[transport.js:isPublicRadioAddress]`
- `[transport.js:radioProxyDestination]`
- `[transport.js:resolveRadioProxyAddresses]`
- `[transport.js:fetchPinnedRadioResponse]`

## Invariants
- None

## Side Effects
- [catalog.js:27]: `import { readResponseTextCapped } from '../common/http.js';`
- [catalog.js:266]: `throw new Error('Radio Browser exceeded the country query limit');`
- [catalog.js:337]: `if (!broadQueryHealthy) healthReasons.push('broad-query-unhealthy');`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/radio/...`
