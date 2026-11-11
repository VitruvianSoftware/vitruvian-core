# App

## Overview
Component package providing implementation for `apps/suites/tabula/infra/app`.

## Interface
- Internal implementation components
- Subdirectory: [cmd](./cmd/README.md)
- Subdirectory: [revision](./revision/README.md)

## Invariants
- [main.go:75]: `project := cfg.Require("project") // the env's oss-floating project id`
- [main.go:80]: `env := cfg.Require("environment")`
- [main.go:81]: `runtimeSA := cfg.Require("runtimeServiceAccount")`

## Side Effects
- [main.go:171]: `// arbitrary opener. Unset, it falls back to http://localhost:3000`

## Verification
- Run: `bazel test //apps/suites/tabula/infra/app/...`
