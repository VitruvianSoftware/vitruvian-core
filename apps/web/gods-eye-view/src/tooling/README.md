# Tooling

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/tooling`.

## Interface
- `[fixtureRoot.mjs:makeFixtureRoot]`
- `[trackArrivalObservation.mjs:ARRIVAL_OBSERVATION_MS]`
- `[trackArrivalObservation.mjs:ARRIVAL_MAX_ERROR_DEG]`
- `[trackArrivalObservation.mjs:ARRIVAL_MAX_ATTEMPTS]`
- `[trackArrivalObservation.mjs:observeArrivalRotation]`
- `[trackArrivalObservation.mjs:arrivalAngleViolated]`
- `[trackArrivalObservation.mjs:observeArrivalRotationWithRetry]`
- `[trackArrivalObservation.mjs:arrivalRotationPassed]`

## Invariants
- [allowedHosts.test.mjs:24]: `import assert from 'node:assert/strict';`
- [allowedHosts.test.mjs:35]: `assert.deepEqual(resolveAllowedHosts(), DEFAULT_ALLOWED_HOSTS);`
- [allowedHosts.test.mjs:36]: `assert.equal(resolveAllowedHosts().includes(true), false);`
- [applicationHtml.test.mjs:24]: `import assert from 'node:assert/strict';`
- [applicationHtml.test.mjs:34]: `assert.deepEqual(hosts, ['scene-chrome', 'cockpit', 'display-controls', 'comm...`
- [applicationHtml.test.mjs:35]: `assert.deepEqual([...hosts].sort(), Object.keys(APPLICATION_VIEWS).sort());`
- [boundedCache.test.mjs:29]: `import assert from 'node:assert/strict';`
- [boundedCache.test.mjs:55]: `assert.equal(await reader.get(`k${i}`), `v${i}`);`
- [boundedCache.test.mjs:56]: `assert.equal(reader.memorySize, 10);`
- [changelogFragments.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [allowedHosts.test.mjs:25]: `import { request as httpRequest } from 'node:http';`
- [changelogFragments.test.mjs:29]: `writeFile,`
- [changelogFragments.test.mjs:56]: `await writeFile(`
- [changelogFragments.test.mjs:60]: `await writeFile(path.join(root, 'CHANGELOG.md'), EXISTING);`
- [environmentProviders.test.mjs:86]: `t.mock.method(fsp, 'writeFile', async () => {});`
- [environmentProviders.test.mjs:116]: `t.mock.method(globalThis, 'fetch', () => {`
- [environmentProviders.test.mjs:117]: `throw Error('construction must not fetch');`
- [format.test.mjs:29]: `writeFile,`
- [format.test.mjs:42]: `await writeFile(`
- [format.test.mjs:46]: `await writeFile(`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/tooling/...`
