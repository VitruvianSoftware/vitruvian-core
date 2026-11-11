# Space

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/space`.

## Interface
- `[celestrak.js:celestrakProxy]`
- `[cooldown.js:providerCooldownMs]`
- `[launch-library.js:LL2_CACHE_TTL_MS]`
- `[launch-library.js:launchLibraryRequestHeaders]`
- `[launch-library.js:rocketLaunchesProxy]`

## Invariants
- None

## Side Effects
- [celestrak.js:31]: `import { readResponseTextCapped } from '../common/http.js';`
- [celestrak.js:45]: `* CelesTrak asks clients not to re-fetch GP data more than ~every 2 h and`
- [celestrak.js:137]: `await fsp.writeFile(diskPath(group), JSON.stringify(entry), 'utf8');`
- [cooldown.js:23]: `/** Bound an upstream Retry-After delay (seconds or HTTP date). */`
- [launch-library.js:29]: `} from '../common/http.js';`
- [launch-library.js:81]: `await fsp.writeFile(cachePath, JSON.stringify(entry), 'utf8');`
- [launch-library.js:110]: `const upstream = await fetch(url, {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/space/...`
