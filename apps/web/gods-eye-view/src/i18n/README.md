# I18N

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/i18n`.

## Interface
- `[index.js:bindLocale]`
- `[index.js:onLocaleChange]`
- `[index.js:notifyLocaleChange]`
- `[index.js:getCatalog]`
- `[index.js:getLocale]`
- `[index.js:isolate]`
- `[index.js:keepCodesWithValues]`
- `[index.js:setLocale]`
- `[index.js:t]`
- `[index.js:tn]`
- `[index.js:translateKnown]`
- `[index.js:msg]`
- `[index.js:formatNumber]`
- `[index.js:formatDate]`
- `[index.js:formatUtcDayMonth]`
- `[index.js:formatRelativeTime]`
- `[index.js:applyDocumentTranslations]`
- `[index.js:persistLocale]`
- `[locale.js:LOCALE_STORAGE_KEY]`
- `[locale.js:DEFAULT_LOCALE]`

## Invariants
- [ar-display.test.mjs:24]: `import assert from 'node:assert/strict';`
- [ar-display.test.mjs:51]: `assert.equal(`
- [ar-display.test.mjs:59]: `assert.equal(`
- [catalog.test.mjs:24]: `import assert from 'node:assert/strict';`
- [catalog.test.mjs:41]: `assert.deepEqual(`
- [catalog.test.mjs:54]: `assert.deepEqual(`
- [empty-translation.test.mjs:25]: `import assert from 'node:assert/strict';`
- [empty-translation.test.mjs:41]: `assert.ok(`
- [empty-translation.test.mjs:45]: `assert.ok(`
- [firms-live-zh.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- [catalog.test.mjs:216]: `assert.deepEqual(texts('stats.error = `${name} fetch error`;'), [`
- [catalog.test.mjs:217]: `'fetch error',`
- [catalog.test.mjs:235]: `assert.deepEqual(texts("stats.error = t('GBFS fetch error');"), []);`
- [index.js:315]: `typeof value === 'string' ? /^(\d{4})-(\d{2})-(\d{2})/.exec(value) : null;`
- [kartaviewMessages.test.mjs:62]: `test('KartaView HTTP and refusal codes keep their number in every language', ...`
- [kartaviewMessages.test.mjs:65]: `const http = 'KartaView answered HTTP 503';`
- [kartaviewMessages.test.mjs:67]: `assert.equal(translateStreetLevelError(http), http);`
- [layerStatusText.test.mjs:33]: `['../layers/bikeshare/controls.js', 'GBFS fetch error'],`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/i18n/...`
