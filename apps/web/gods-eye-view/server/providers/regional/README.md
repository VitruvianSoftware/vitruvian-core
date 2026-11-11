# Regional

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/regional`.

## Interface
- `[nominatimCache.js:NOMINATIM_CACHE_TTL_MS]`
- `[nominatimCache.js:normalizePlaceName]`
- `[nominatimCache.js:createNominatimCache]`
- `[nominatimGate.js:PUBLIC_NOMINATIM_SEARCH]`
- `[nominatimGate.js:NOMINATIM_MAX_PENDING]`
- `[nominatimGate.js:resolveNominatimSettings]`
- `[nominatimGate.js:parseRetryAfter]`
- `[nominatimGate.js:createGateStateStore]`
- `[nominatimGate.js:createNominatimGate]`
- `[nominatimGate.js:sharedNominatimGate]`
- `[nominatimGate.js:setSharedNominatimGate]`
- `[nominatimGate.js:isNominatimBusy]`
- `[outlineSelect.js:OUTLINE_KINDS]`
- `[outlineSelect.js:OUTLINE_POLYGON_THRESHOLD]`
- `[outlineSelect.js:acceptsOutlineClass]`
- `[outlineSelect.js:capOutlineVertices]`
- `[outlineSelect.js:selectOutlineResult]`
- `[outlineSelect.js:outlineAt]`
- `[outlineSelect.js:outlineBias]`
- `[place.js:upstreamQuery]`

## Invariants
- [outlineSelect.js:403]: `* Settlements require one complete normalized name or explicit returned alias.`

## Side Effects
- [briefing.js:27]: `import { validRegionalPoint } from './query.js';`
- [briefing.js:28]: `import { coalesceProxyRequest } from '../common/http.js';`
- [briefing.js:85]: `newsQuery: news.query,`
- [http.js:26]: `} from '../common/http.js';`
- [http.js:58]: `const response = await fetch(url, {`
- [news.js:23]: `import { fetchRegionalText, fetchRegionalJson } from './http.js';`
- [news.js:41]: `new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>`, 'i').exec(`
- [news.js:62]: `if (!title || !['http:', 'https:'].includes(parsedUrl.protocol)) continue;`
- [nominatimCache.js:96]: `const entry = JSON.parse(await fs.readFile(fileFor(key), 'utf8'));`
- [nominatimCache.js:119]: `await fs.mkdir(dir, { recursive: true, mode: 0o700 });`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/regional/...`
