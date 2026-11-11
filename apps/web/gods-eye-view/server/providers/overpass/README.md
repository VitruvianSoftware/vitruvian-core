# Overpass

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/overpass`.

## Interface
- `[osmFeatures.js:OSM_FEATURE_LIMITS]`
- `[osmFeatures.js:compileOsmFeatureQuery]`
- `[osmFeatures.js:summarizeOsmFeatures]`
- `[osmFeaturesRoute.js:installOsmFeaturesRoute]`
- `[transport.js:overpassNotConfigured]`

## Invariants
- [requestAdmission.test.mjs:24]: `import assert from 'node:assert/strict';`
- [requestAdmission.test.mjs:58]: `assert.equal(sanitizeOverpassBody(form(query)).ok, false, query);`
- [requestAdmission.test.mjs:70]: `assert.equal(result.ok, true, query);`

## Side Effects
- [cache.js:23]: `import { coalesceProxyRequest } from '../common/http.js';`
- [cache.js:24]: `import { isOverpassBoundaryQuery } from './query.js';`
- [cache.js:41]: `/** Disk TTL for a query: boundary geometry keeps for a month, the rest 7 day...`
- [constants.js:33]: `/** Parse only operator-supplied HTTP(S) endpoints; private instances are all...`
- [constants.js:40]: `!['http:', 'https:'].includes(url.protocol) ||`
- [constants.js:92]: `* matched on the query alone. Shared by both caches fed by these upstreams.`
- [osmFeatures.js:29]: `* The request carries a preset id, a box, a mode and a limit — never query`
- [osmFeatures.js:30]: `* text. The server writes the Overpass query itself and bounds it: box size`
- [osmFeatures.js:31]: `* per mode (a count may cover more ground than a fetch), result count,`
- [osmFeaturesRoute.js:54]: `* One upstream Overpass query at a time, with identical requests sharing it`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/overpass/...`
