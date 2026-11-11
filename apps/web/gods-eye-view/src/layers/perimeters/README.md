# Perimeters

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/perimeters`.

## Interface
- `[cards.js:PERIMETER_OVERLAY_SOURCE_ID]`
- `[cards.js:containmentAccent]`
- `[cards.js:perimeterAnchorDegrees]`
- `[cards.js:buildIncidentCard]`
- `[inciweb.js:resolveInciwebNodeLink]`
- `[inciweb.js:inciwebNodeId]`
- `[inciweb.js:isCurrentPublication]`
- `[inciweb.js:createInciwebPublicationSource]`
- `[inciweb.js:findInciwebLink]`
- `[inciweb.js:createInciwebIndexSource]`
- `[index.js:containmentColor]`
- `[index.js:createFirePerimetersLayer]`
- `[records.js:normalizeFirePerimeterSnapshot]`
- `[source.js:createWfigsPerimeterSource]`

## Invariants
- [cards.i18n.test.mjs:27]: `import assert from 'node:assert/strict';`
- [cards.i18n.test.mjs:52]: `assert.equal(card.title, 'FIRE · Lake');`
- [cards.i18n.test.mjs:53]: `assert.deepEqual(card.details, [`
- [cards.test.mjs:24]: `import assert from 'node:assert/strict';`
- [cards.test.mjs:43]: `assert.ok(Math.abs(anchor.lon - -108.1) < 1e-9);`
- [cards.test.mjs:44]: `assert.ok(Math.abs(anchor.lat - 35.1) < 1e-9);`
- [inciweb.js:104]: `// Without a discovery date, require recent editorial activity on the page.`
- [inciweb.test.mjs:24]: `import assert from 'node:assert/strict';`
- [inciweb.test.mjs:75]: `assert.equal(`
- [inciweb.test.mjs:79]: `assert.equal(`

## Side Effects
- [cards.js:147]: `const match = /^Type ([1-5]) Incident$/.exec(complexity);`
- [inciweb.js:23]: `/** InciWeb incident catalog: full-index fetch and WFIGS-name matching. */`
- [inciweb.js:94]: `const match = /^https:\/\/inciweb\.wildfire\.gov\/node\/(\d+)$/.exec(`
- [inciweb.js:127]: `/** Fetch one publication's created/changed timestamps for currency checks. */`
- [inciweb.test.mjs:287]: `await assert.rejects(failing.getPublication('1'), /InciWeb HTTP 503/);`
- [inciweb.test.mjs:331]: `await assert.rejects(failing.getIndex(), /InciWeb HTTP 503/);`
- [index.js:106]: `* fetch only costs the link line, never the perimeter refresh — the`
- [index.js:325]: `// A stale snapshot is as old as its fetch, not this poll.`
- [index.js:404]: `console.warn('[Data:FirePerimeters] Fetch error:', e);`
- [ownership.test.mjs:331]: `throw new Error('InciWeb HTTP 503');`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/perimeters/...`
