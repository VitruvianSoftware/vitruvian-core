# Scripts

## Overview
Component package providing implementation for `apps/web/gods-eye-view/scripts`.

## Interface
- `[assemble-changelog.mjs:FRAGMENT_DIR]`
- `[assemble-changelog.mjs:STAGING_DIR]`
- `[assemble-changelog.mjs:orderFragmentNames]`
- `[assemble-changelog.mjs:assembleChangelog]`
- `[assemble-changelog.mjs:recoverInterruptedBatch]`
- `[assemble-changelog.mjs:assembleFragments]`
- `[build-admin-packs.mjs:SOURCES]`
- `[build-admin-packs.mjs:PARAMS]`
- `[build-admin-packs.mjs:fetchPinned]`
- `[build-admin-packs.mjs:ringAreaKm2]`
- `[build-admin-packs.mjs:signedArea]`
- `[build-admin-packs.mjs:simplifyPolygons]`
- `[build-admin-packs.mjs:unitTolerance]`
- `[build-admin-packs.mjs:simplifyUnit]`
- `[build-admin-packs.mjs:encodeUnit]`
- `[build-admin-packs.mjs:unzip]`
- `[build-admin-packs.mjs:readShp]`
- `[build-admin-packs.mjs:readDbf]`
- `[build-admin-packs.mjs:shpPolygons]`
- `[build-admin-packs.mjs:pointInRing]`
- Subdirectory: [fixtures](./fixtures/README.md)
- Subdirectory: [src](./src/README.md)
- Subdirectory: [voice-bench](./voice-bench/README.md)

## Invariants
- [bazel-unit-tests.mjs:42]: `const requirePatches = patches ? `--require ${JSON.stringify(patches)} ` : '';`
- [build-owner-flags.mjs:49]: `const require = createRequire(import.meta.url);`
- [build-owner-flags.mjs:51]: `path.dirname(require.resolve('flag-icons/package.json')),`
- [build-owner-flags.mjs:54]: `const FLAG_ICONS_VERSION = require('flag-icons/package.json').version;`
- [build-wof-neighborhoods.py:106]: `raise ValueError(f'{name}: SHA-256 {digest.hexdigest()} is not the pinned {sh...`
- [build-wof-neighborhoods.py:139]: `raise ValueError(f'encoded geometry invalid: {why}')`
- [build-wof-neighborhoods.py:180]: `raise ValueError(f'{key}: reviewed source is absent from the pinned registry')`
- [focus-allocation-check.mjs:24]: `import assert from 'node:assert/strict';`
- [focus-allocation-check.mjs:57]: `assert.ok(Number.isFinite(checksum));`
- [focus-allocation-check.mjs:137]: `assert.ok(`

## Side Effects
- [assemble-changelog.mjs:60]: `const match = FRAGMENT_NAME.exec(name);`
- [assemble-changelog.mjs:173]: `await io.writeFile(`
- [bazel-unit-tests.mjs:27]: `* JS_BINARY__NODE_BINARY variable. Several upstream tests spawn the dev`
- [build-admin-packs.mjs:47]: `import { mkdir, readFile, writeFile } from 'node:fs/promises';`
- [build-admin-packs.mjs:148]: `const response = await fetch(url);`
- [build-admin-packs.mjs:149]: `if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);`
- [build-bright-stars.mjs:150]: `const response = await fetch(SOURCE_URL);`
- [build-bright-stars.mjs:151]: `if (!response.ok) throw new Error(`${SOURCE_URL}: HTTP ${response.status}`);`
- [build-bright-stars.mjs:156]: `const bytes = fs.readFileSync(file);`
- [build-census-places.mjs:50]: `import { mkdir, readdir, rm, writeFile } from 'node:fs/promises';`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/scripts/...`
