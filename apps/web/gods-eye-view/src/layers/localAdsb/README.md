# Localadsb

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/layers/localAdsb`.

## Interface
- `[card.js:localAdsbTitle]`
- `[card.js:localAdsbIsUat]`
- `[card.js:localAdsbReceiverLine]`
- `[card.js:localAdsbSourceText]`
- `[card.js:localAdsbClassLine]`
- `[card.js:localAdsbCardModel]`
- `[enrichment.js:localAdsbClass]`
- `[enrichment.js:createLocalAdsbEnrichment]`
- `[feedNames.js:localReceiverFeedName]`
- `[feeds.js:LOCAL_RECEIVERS_URL]`
- `[feeds.js:createLocalReceiverFeeds]`
- `[index.js:createLocalAdsbLayer]`
- `[models.js:createLocalAdsbModels]`
- `[motion.js:LOCAL_ADSB_HISTORY_MS]`
- `[motion.js:LOCAL_ADSB_HISTORY_POINTS]`
- `[motion.js:LocalAdsbMotion]`
- `[policy.js:LAYER_ID]`
- `[policy.js:LAYER_NAME]`
- `[policy.js:LAYER_SOURCE]`
- `[policy.js:LOCAL_ADSB_COLOR]`

## Invariants
- [card.i18n.test.mjs:26]: `import assert from 'node:assert/strict';`
- [card.i18n.test.mjs:45]: `assert.deepEqual(localAdsbCardModel(record, 5000).details, [`
- [card.i18n.test.mjs:52]: `assert.equal(`
- [card.test.mjs:24]: `import assert from 'node:assert/strict';`
- [card.test.mjs:40]: `assert.equal(details[1], 'ALT 12,500 FT · GS 240 KT · TRK 0°');`
- [feeds.test.mjs:24]: `import assert from 'node:assert/strict';`
- [feeds.test.mjs:75]: `assert.deepEqual(calls, [LOCAL_RECEIVERS_URL]);`
- [feeds.test.mjs:76]: `assert.equal(feeds.getState().configured, false);`
- [index.test.mjs:23]: `import assert from 'node:assert/strict';`
- [index.test.mjs:237]: `assert.equal(layer.id, 'local-adsb');`

## Side Effects
- [enrichment.js:89]: `function enqueue(key, query, apply, priority) {`
- [enrichment.js:92]: `const job = { query, apply };`
- [enrichment.js:114]: `.then(() => source.getEnrichment(job.query, { signal }))`
- [feeds.js:73]: `* @param {typeof fetch} [options.fetchImpl]`
- [feeds.js:81]: `fetchImpl = (...args) => globalThis.fetch(...args),`
- [index.test.mjs:477]: `async getEnrichment(query) {`
- [index.test.mjs:478]: `queries.push(`${query.kind}:${query.id}`);`
- [index.test.mjs:479]: `if (query.kind === 'type')`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/layers/localAdsb/...`
