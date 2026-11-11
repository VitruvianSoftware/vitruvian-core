# Common

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/common`.

## Interface
- `[boundedCache.js:createBoundedCache]`
- `[compress.js:acceptsGzip]`
- `[compress.js:gzipBody]`
- `[compress.js:encodedBody]`
- `[geo.js:haversineKm]`
- `[http.js:readCappedResponseText]`
- `[query.js:requiredFiniteQueryNumber]`
- `[query.js:clampInt]`
- `[rate-limit.js:resolvePerMinuteCap]`
- `[rate-limit.js:makeCostRateLimiter]`
- `[rate-limit.js:clientKey]`
- `[rate-limit.js:isLoopbackPeer]`
- `[rate-limit.js:clientNetworkKey]`
- `[same-site.js:admitSameSite]`
- `[same-site.js:sameSiteGated]`
- `[same-site.js:admitSameSiteKeyless]`
- `[textChat.js:createTextChatHandler]`
- `[textInstructions.js:TEXT_WORDING]`
- `[textInstructions.js:textInstructions]`
- `[textTools.js:invalidCalls]`

## Invariants
- [rateLimitKeys.test.mjs:24]: `import assert from 'node:assert/strict';`
- [rateLimitKeys.test.mjs:30]: `assert.equal(clientNetworkKey(req('2001:db8:1:2::1')), '2001:db8:1:2::/64');`
- [rateLimitKeys.test.mjs:31]: `assert.equal(`
- [request.test.mjs:24]: `import assert from 'node:assert/strict';`
- [request.test.mjs:30]: `req.pause = () => assert.fail('The reader must keep draining');`
- [request.test.mjs:32]: `assert.fail('The reader must preserve the response socket');`

## Side Effects
- [boundedCache.js:142]: `await fsp.writeFile(fileFor(key), JSON.stringify(entry));`
- [compress.js:49]: `* @param {import('node:http').IncomingMessage} request`
- [compress.js:90]: `* @param {import('node:http').IncomingMessage} request`
- [http.js:31]: `* Read a fetch Response body as text while enforcing a hard byte cap during`
- [http.js:35]: `* @param {Response} upstream - fetch() response.`
- [rate-limit.js:98]: `const v4 = IPV4_MAPPED_RE.exec(raw)?.[1] ?? raw;`
- [rate-limit.js:110]: `* @param {import('node:http').IncomingMessage} req`
- [rate-limit.js:115]: `const mapped = IPV4_MAPPED_RE.exec(address);`
- [same-site.js:31]: `* Sec-Fetch-Site other than same-origin/none, or reverse-proxy headers) while`
- [same-site.js:33]: `* @param {import('node:http').IncomingMessage} req`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/common/...`
