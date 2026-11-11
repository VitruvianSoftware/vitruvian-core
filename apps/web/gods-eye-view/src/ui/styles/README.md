# Styles

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/ui/styles`.

## Interface
- Internal implementation components

## Invariants
- [english-css-parity.test.mjs:27]: `import assert from 'node:assert/strict';`
- [english-css-parity.test.mjs:64]: `assert.equal(rules.length, 1);`
- [english-css-parity.test.mjs:65]: `assert.equal(declaration(rules[0], 'min-width'), '82px');`

## Side Effects
- [english-css-parity.test.mjs:42]: `while ((m = re.exec(source))) {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/ui/styles/...`
