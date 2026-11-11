# Layerpanel

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui/layerPanel`.

## Interface
- Internal implementation components

## Invariants
- [layerRows.test.mjs:27]: `import assert from 'node:assert/strict';`
- [layerRows.test.mjs:56]: `assert.equal(element.className, 'data-toggle-row');`
- [layerRows.test.mjs:60]: `assert.equal(element.classList.contains('data-toggle-row--count-line'), true);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/layerPanel/...`
