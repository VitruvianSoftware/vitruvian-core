# Prisma

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/api/prisma`.

## Interface
- Internal implementation components
- Subdirectory: [migrations](./migrations/README.md)

## Invariants
- None

## Side Effects
- [schema.prisma:2]: `provider            = "prisma-client"`
- [schema.prisma:4]: `output              = "../src/generated/prisma"`
- [schema.prisma:11]: `// Prisma 7: the connection URL lives in ../prisma.config.ts (migrate) and`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/api/prisma/...`
