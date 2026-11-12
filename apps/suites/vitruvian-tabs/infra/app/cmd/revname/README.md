# Revname

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/infra/app/cmd/revname`.

## Interface
- Internal implementation components

## Invariants
- [main.go:56]: `// is ../../main.go (cfg.Require/Get on the same names); keep them in sync — the`
- [main.go:79]: `// project and environment are Require()d by the app stack — absent means a`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/infra/app/cmd/revname/...`
