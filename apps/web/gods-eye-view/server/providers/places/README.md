# Places

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/places`.

## Interface
- `[google-key.js:keylessGooglePlacesResponse]`
- `[google-key.js:keylessGoogleGeocodeResponse]`
- `[google-key.js:googleServerApiKey]`
- `[google.js:GOOGLE_DEFAULT_PER_MIN]`
- `[google.js:validatePlacesCoordinates]`
- `[google.js:validateGeocodeAddress]`
- `[google.js:geocodeBounds]`
- `[google.js:googlePlacesContextProxy]`
- `[routes.js:ROUTE_UPSTREAM_MIN_INTERVAL_MS]`
- `[routes.js:ROUTE_UPSTREAM_QUEUE_MAX]`
- `[routes.js:_resetRouteUpstreamForTest]`
- `[routes.js:_setRouteUpstreamIntervalForTest]`
- `[routes.js:_routeInflightCountForTest]`
- `[routes.js:installRouteMiddleware]`

## Invariants
- None

## Side Effects
- [google.js:30]: `import { readResponseJsonCapped } from '../common/http.js';`
- [google.js:83]: `/** Longest accepted geocoder query. Real place names are far shorter. */`
- [google.js:96]: `/** Validate a free-text geocoder query before consuming request quota. */`
- [routes.js:25]: `import { readResponseTextCapped } from '../common/http.js';`
- [routes.js:44]: `* fetch. The FOSSGIS servers ask for no heavy use; the cheapest way to honour`
- [routes.js:167]: `* Fetch one route from the routing service and project it.`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/places/...`
