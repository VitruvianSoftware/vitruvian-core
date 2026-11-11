# Src

## Overview
Component package providing implementation for `apps/web/backstage/packages/app/src`.

## Interface
- `[apis.ts:apis]`
- Subdirectory: [components](./components/README.md)
- Subdirectory: [theme](./theme/README.md)

## Invariants
- [tableRowIds.test.ts:29]: `path.dirname(require.resolve("@backstage/core-components/package.json")),`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/backstage/packages/app/src/...`
