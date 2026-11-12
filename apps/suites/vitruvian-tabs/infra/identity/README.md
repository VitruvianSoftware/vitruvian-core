# Identity

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/infra/identity`.

## Interface
- Internal implementation components

## Invariants
- [main.go:70]: `return cfg.Require(legacyKey)`
- [main.go:76]: `projectID := cfg.Require("project")                                      // t...`
- [main.go:164]: `// Verification DNS-TXT (the Cloud Run DomainMapping precondition).`

## Side Effects
- [main.go:28]: `// `prisma migrate deploy`, and the Cloudflare token accessors).`
- [main.go:121]: `// CI (`prisma migrate deploy --phase expand` against TABULA_DATABASE_URL)`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/infra/identity/...`
