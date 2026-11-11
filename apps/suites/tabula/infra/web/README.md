# Web

## Overview
Component package providing implementation for `apps/suites/tabula/infra/web`.

## Interface
- Internal implementation components
- Subdirectory: [revision](./revision/README.md)

## Invariants
- [main.go:43]: `project := cfg.Require("project")`
- [main.go:48]: `env := cfg.Require("environment")`
- [main.go:49]: `runtimeSA := cfg.Require("runtimeServiceAccount")`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/tabula/infra/web/...`
