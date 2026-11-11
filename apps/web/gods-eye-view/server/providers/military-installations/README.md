# Military Installations

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/providers/military-installations`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [cache.js:167]: `await fsp.writeFile(temp, JSON.stringify(entry));`
- [constants.js:68]: `* key and a new upstream query. Snapping the bbox OUTWARD onto a coarse grid`
- [query.js:24]: `import { requiredFiniteQueryNumber } from '../common/query.js';`
- [query.js:55]: `* The key's precision must match the precision of the bounds the QUERY uses, or`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/providers/military-installations/...`
