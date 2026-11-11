# Src

## Overview
Component package providing implementation for `apps/web/backstage/packages/backend/src`.

## Interface
- Internal implementation components
- Subdirectory: [auth](./auth/README.md)
- Subdirectory: [catalog](./catalog/README.md)
- Subdirectory: [cloudRun](./cloudRun/README.md)
- Subdirectory: [gcp](./gcp/README.md)
- Subdirectory: [permissions](./permissions/README.md)
- Subdirectory: [proxy](./proxy/README.md)
- Subdirectory: [scaffolder](./scaffolder/README.md)
- Subdirectory: [scorecards](./scorecards/README.md)

## Invariants
- None

## Side Effects
- [index.ts:77]: `// generated bazel-* templates fail mid-run: fetch:template renders the project`

## Verification
- Run: `bazel test //apps/web/backstage/packages/backend/src/...`
