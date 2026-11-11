# App

## Overview
Component package providing implementation for `apps/web/oauth-user-inspector/infra/app`.

## Interface
- Internal implementation components

## Invariants
- [main.go:80]: `project := cfg.Require("project") // the env's oss-floating project id`
- [main.go:85]: `env := cfg.Require("environment")`
- [main.go:86]: `runtimeSA := cfg.Require("runtimeServiceAccount")`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/oauth-user-inspector/infra/app/...`
