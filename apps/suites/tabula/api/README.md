# Api

## Overview
Component package providing implementation for `apps/suites/tabula/api`.

## Interface
- Internal implementation components
- Subdirectory: [prisma](./prisma/README.md)
- Subdirectory: [rs](./rs/README.md)

## Invariants
- None

## Side Effects
- [prisma.config.ts:23]: `// Prisma 7 project config (replaces schema-file `url` + package.json#prisma).`
- [prisma.config.ts:27]: `// driver adapter in src/lib/prisma.ts.`
- [prisma.config.ts:28]: `import { defineConfig, env } from "prisma/config";`

## Verification
- Run: `bazel test //apps/suites/tabula/api/...`
